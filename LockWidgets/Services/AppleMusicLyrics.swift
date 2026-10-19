import Foundation
import SQLite3

/// Apple Music's own time-synced lyrics, read from the copy Music keeps in its local cache.
/// When Music plays a catalogue song it fetches the song's lyrics (TTML) from Apple and caches the response;
/// this finds that response for the current track. Nothing is downloaded from anywhere else.
enum AppleMusicLyrics {
    struct Line: Equatable {
        let begin: Double
        let end: Double
        let text: String
    }

    private static var cacheFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/com.apple.Music")
    }

    /// When Music's cache last changed, from its files' dates: a cheap check of whether looking again could
    /// find something new.
    static var cacheChanged: Date? {
        ["Cache.db", "Cache.db-wal"]
            .compactMap { (try? FileManager.default.attributesOfItem(atPath: cacheFolder.appendingPathComponent($0).path))?[.modificationDate] as? Date }
            .max()
    }

    /// Lyrics for a track, matched by title and length. nil when Music hasn't cached any.
    static func lyrics(title: String, artist _: String, duration: Double) -> [Line]? {
        for response in cachedResponses() {
            guard let songs = (try? JSONSerialization.jsonObject(with: response) as? [String: Any])?["data"] as? [[String: Any]] else { continue }
            for song in songs {
                guard let attributes = song["attributes"] as? [String: Any],
                      let name = attributes["name"] as? String,
                      matches(name, title),
                      abs((attributes["durationInMillis"] as? Double ?? 0) / 1000 - duration) < 4,
                      let ttml = ttml(in: song)
                else { continue }
                let lines = TTMLParser().parse(ttml)
                if !lines.isEmpty { return lines }
            }
        }
        return nil
    }

    /// Artwork for a song Music is streaming, from the same cached catalogue entry. Music's scripting only
    /// hands out artwork for songs in the library, so this covers the rest. nil until Music has cached it.
    static func artworkURL(title: String, duration: Double, size: Int = 300) -> URL? {
        for response in cachedResponses() {
            guard let songs = (try? JSONSerialization.jsonObject(with: response) as? [String: Any])?["data"] as? [[String: Any]] else { continue }
            for song in songs {
                guard let attributes = song["attributes"] as? [String: Any],
                      let name = attributes["name"] as? String,
                      matches(name, title),
                      abs((attributes["durationInMillis"] as? Double ?? 0) / 1000 - duration) < 4,
                      let template = (attributes["artwork"] as? [String: Any])?["url"] as? String
                else { continue }
                // The URL is a template: {w}x{h} for the size, {c} for the crop and {f} for the format.
                let link = template
                    .replacingOccurrences(of: "{w}", with: "\(size)")
                    .replacingOccurrences(of: "{h}", with: "\(size)")
                    .replacingOccurrences(of: "{c}", with: "bb")
                    .replacingOccurrences(of: "{f}", with: "jpg")
                return URL(string: link)
            }
        }
        return nil
    }

    private static func ttml(in song: [String: Any]) -> String? {
        let relationships = song["relationships"] as? [String: Any]
        for key in ["syllable-lyrics", "lyrics"] {
            if let entries = (relationships?[key] as? [String: Any])?["data"] as? [[String: Any]],
               let attributes = entries.first?["attributes"] as? [String: Any],
               let ttml = (attributes["ttmlLocalizations"] ?? attributes["ttml"]) as? String
            {
                return ttml
            }
        }
        return nil
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "’", with: "'")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ catalogue: String, _ title: String) -> Bool {
        let a = normalized(catalogue)
        let b = normalized(title)
        return a == b || a.hasPrefix(b) || b.hasPrefix(a)
    }

    // MARK: Cache

    /// Bodies of Music's cached catalogue responses that asked for lyrics, newest first.
    private static func cachedResponses() -> [Data] {
        // Music keeps the database open, so read from a private copy, one per lookup, since lyrics and
        // artwork can be looked up at the same time.
        let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("LockWidgetsMusicCache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for suffix in ["", "-wal", "-shm"] {
            let source = cacheFolder.appendingPathComponent("Cache.db" + suffix)
            let target = scratch.appendingPathComponent("Cache.db" + suffix)
            try? FileManager.default.removeItem(at: target)
            try? FileManager.default.copyItem(at: source, to: target)
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(scratch.appendingPathComponent("Cache.db").path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(database) }

        let query = """
        SELECT d.isDataOnFS, d.receiver_data FROM cfurl_cache_response r
        JOIN cfurl_cache_receiver_data d ON d.entry_ID = r.entry_ID
        WHERE r.request_key LIKE '%lyrics%' ORDER BY r.time_stamp DESC LIMIT 300
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }

        var results: [Data] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let onDisk = sqlite3_column_int(statement, 0) == 1
            let length = Int(sqlite3_column_bytes(statement, 1))
            guard let bytes = sqlite3_column_blob(statement, 1), length > 0 else { continue }
            let blob = Data(bytes: bytes, count: length)
            if onDisk {
                // The column holds the name of the file in fsCachedData.
                let name = String(decoding: blob, as: UTF8.self)
                if let data = try? Data(contentsOf: cacheFolder.appendingPathComponent("fsCachedData").appendingPathComponent(name)) {
                    results.append(data)
                }
            } else {
                results.append(blob)
            }
        }
        return results
    }
}

/// Reads the <p begin end> lines from Apple's lyrics TTML.
private final class TTMLParser: NSObject, XMLParserDelegate {
    private var lines: [AppleMusicLyrics.Line] = []
    private var current: (begin: Double, end: Double, text: String)?
    /// Background vocals arrive in spans marked x-bg; leave them out so lines read like Music's main text.
    private var backgroundDepth = 0

    func parse(_ ttml: String) -> [AppleMusicLyrics.Line] {
        let parser = XMLParser(data: Data(ttml.utf8))
        parser.delegate = self
        parser.parse()
        return lines.sorted { $0.begin < $1.begin }
    }

    func parser(_: XMLParser, didStartElement name: String, namespaceURI _: String?, qualifiedName _: String?, attributes: [String: String] = [:]) {
        if name == "p", let begin = attributes["begin"].flatMap(Self.seconds), let end = attributes["end"].flatMap(Self.seconds) {
            current = (begin, end, "")
        } else if name == "span", attributes["ttm:role"] == "x-bg" || backgroundDepth > 0 {
            backgroundDepth += 1
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        guard current != nil, backgroundDepth == 0 else { return }
        current?.text += string
    }

    func parser(_: XMLParser, didEndElement name: String, namespaceURI _: String?, qualifiedName _: String?) {
        if name == "span", backgroundDepth > 0 {
            backgroundDepth -= 1
        } else if name == "p", let line = current {
            let text = line.text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            lines.append(.init(begin: line.begin, end: line.end, text: text))
            current = nil
        }
    }

    /// "12.345", "1:02.345" or "1:01:02.345" to seconds.
    static func seconds(_ text: String) -> Double? {
        var total = 0.0
        for part in text.split(separator: ":") {
            guard let value = Double(part) else { return nil }
            total = total * 60 + value
        }
        return total
    }
}

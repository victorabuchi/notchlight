import Foundation

/// Synced lyrics from LRCLIB (lrclib.net), a free public library of lyrics, for songs Music hasn't fetched
/// Apple's own lyrics for: songs from a station or autoplay, and songs playing in Spotify. Only the song's
/// title, artist, album and length are sent.
enum LRCLib {
    private struct Record: Decodable {
        let duration: Double?
        let syncedLyrics: String?
    }

    /// The song's timed lines, or nil when LRCLIB has no synced lyrics for it.
    static func lyrics(for track: NowPlayingStore.Track) async -> [AppleMusicLyrics.Line]? {
        if let exact = await request("get", [
            "artist_name": track.artist,
            "track_name": track.title,
            "album_name": track.album,
            "duration": String(Int(track.duration.rounded())),
        ]).flatMap({ try? JSONDecoder().decode(Record.self, from: $0) }),
            let lines = exact.syncedLyrics.map(parse), !lines.isEmpty
        {
            return lines
        }
        // A looser search: titles often differ by "(feat. …)" or "- Remastered".
        let records = await request("search", [
            "artist_name": track.artist,
            "track_name": simplified(track.title),
        ]).flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
        let closest = records
            .filter { $0.syncedLyrics?.isEmpty == false && abs(($0.duration ?? track.duration) - track.duration) < 4 }
            .min { abs(($0.duration ?? 0) - track.duration) < abs(($1.duration ?? 0) - track.duration) }
        guard let lines = closest?.syncedLyrics.map(parse), !lines.isEmpty else { return nil }
        return lines
    }

    /// Asks LRCLIB, trying again a couple of times when it says it's busy.
    private static func request(_ endpoint: String, _ query: [String: String]) async -> Data? {
        var components = URLComponents(string: "https://lrclib.net/api/\(endpoint)")!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("Notchlight (https://notchlight.com)", forHTTPHeaderField: "User-Agent")
        for attempt in 0 ..< 3 {
            guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
            switch (response as? HTTPURLResponse)?.statusCode {
            case 200: return data
            case 429, 502, 503: try? await Task.sleep(for: .seconds(2 * (attempt + 1)))
            default: return nil
            }
        }
        return nil
    }

    private static func simplified(_ title: String) -> String {
        var result = title
        for marker in [" (feat", " [feat", " (with", " - "] {
            if let range = result.range(of: marker, options: .caseInsensitive) {
                result = String(result[..<range.lowerBound])
            }
        }
        return result
    }

    /// Parses "[01:23.45] text" lines, some with several times. An empty line ends the one before it, as a
    /// break; otherwise each line lasts until the next.
    static func parse(_ text: String) -> [AppleMusicLyrics.Line] {
        let pattern = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var entries: [(time: Double, text: String)] = []
        for raw in text.components(separatedBy: .newlines) {
            let matches = pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw))
            guard let last = matches.last, let textRange = Range(last.range, in: raw) else { continue }
            let lyric = raw[textRange.upperBound...].trimmingCharacters(in: .whitespaces)
            for match in matches {
                guard let minutes = Range(match.range(at: 1), in: raw).flatMap({ Double(raw[$0]) }),
                      let seconds = Range(match.range(at: 2), in: raw).flatMap({ Double(raw[$0]) })
                else { continue }
                entries.append((minutes * 60 + seconds, lyric))
            }
        }
        entries.sort { $0.time < $1.time }
        var lines: [AppleMusicLyrics.Line] = []
        for (index, entry) in entries.enumerated() where !entry.text.isEmpty {
            let next = index + 1 < entries.count ? entries[index + 1].time : entry.time + 6
            lines.append(AppleMusicLyrics.Line(begin: entry.time, end: next, text: entry.text))
        }
        return lines
    }
}

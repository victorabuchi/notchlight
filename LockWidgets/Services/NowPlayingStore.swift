import AppKit

/// Reads the current track from Music or Spotify over AppleScript.
/// Only talks to a player that is already running, so it never launches one.
final class NowPlayingStore: ObservableObject {
    static let shared = NowPlayingStore()

    enum Player: String, CaseIterable {
        case music = "com.apple.Music"
        case spotify = "com.spotify.client"

        var name: String {
            switch self {
            case .music: "Apple Music"
            case .spotify: "Spotify"
            }
        }

        var isRunning: Bool {
            !NSRunningApplication.runningApplications(withBundleIdentifier: rawValue).isEmpty
        }

        var trackScript: String {
            switch self {
            case .music:
                """
                tell application id "com.apple.Music"
                    if player state is stopped then return "stopped"
                    set t to current track
                    return {player state is playing, persistent ID of t, name of t, artist of t, album of t, duration of t, player position}
                end tell
                """
            case .spotify:
                """
                tell application id "com.spotify.client"
                    if player state is stopped then return "stopped"
                    set t to current track
                    return {player state is playing, id of t, name of t, artist of t, album of t, (duration of t) / 1000, player position, artwork url of t}
                end tell
                """
            }
        }
    }

    struct Track: Equatable {
        let id: String
        let title: String
        let artist: String
        let album: String
        let duration: Double
        let player: Player
    }

    @Published private(set) var track: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage? {
        didSet { artworkColor = artwork.flatMap(Self.averageColor) }
    }
    /// The artwork's average colour, for tinting the island's waveform.
    @Published private(set) var artworkColor: NSColor?
    /// Set when macOS has blocked LockWidgets from controlling the player.
    @Published private(set) var needsPermission = false

    private var position: Double = 0
    private var positionDate = Date()
    private var timer: Timer?
    private let queue = DispatchQueue(label: "LockWidgets.NowPlaying")

    private init() {
        #if DEBUG
        if WidgetGallery.isRendering { return } // Sample data only.
        #endif
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                self?.poll()
            }
        }
        poll()
    }

    /// Playback position extrapolated from the last poll, so lyrics and progress move smoothly.
    func position(at date: Date) -> Double {
        guard let track else { return 0 }
        let elapsed = isPlaying ? date.timeIntervalSince(positionDate) : 0
        return min(position + elapsed, track.duration)
    }

    enum Command: String {
        case playPause = "playpause"
        case next = "next track"
        case previous = "previous track"
    }

    /// Sends a transport command to whichever player owns the current track.
    func send(_ command: Command) {
        guard let player = track?.player else { return }
        if command == .playPause { isPlaying.toggle() }
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(player.rawValue)\" to \(command.rawValue)")?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.poll() }
        }
    }

    /// Moves the song to a point, in seconds.
    func seek(to seconds: Double) {
        guard let player = track?.player else { return }
        position = seconds
        positionDate = .now
        objectWillChange.send()
        queue.async { [weak self] in
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"\(player.rawValue)\" to set player position to \(Int(seconds))")?.executeAndReturnError(&error)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.poll() }
        }
    }

    private static func averageColor(_ image: NSImage) -> NSColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let color = NSColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255, blue: CGFloat(pixel[2]) / 255, alpha: 1)
        // Lift dark covers so the bars stay visible on black.
        return color.blended(withFraction: color.brightnessComponent < 0.5 ? 0.45 : 0.1, of: .white)
    }

    func openAutomationSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
    }

    func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let results = [Player.music, .spotify].filter(\.isRunning).compactMap { self.read($0) }
            // Prefer whichever player is actually playing.
            let best = results.first { $0.playing } ?? results.first
            DispatchQueue.main.async { self.apply(best) }
        }
    }

    private struct Reading {
        let track: Track
        let playing: Bool
        let position: Double
        let artworkURL: URL?
    }

    private func read(_ player: Player) -> Reading? {
        var error: NSDictionary?
        guard let result = NSAppleScript(source: player.trackScript)?.executeAndReturnError(&error) else {
            if let code = error?[NSAppleScript.errorNumber] as? Int, code == -1743 {
                DispatchQueue.main.async { self.needsPermission = true }
            }
            return nil
        }
        DispatchQueue.main.async { if self.needsPermission { self.needsPermission = false } }
        guard result.numberOfItems >= 7 else { return nil }

        func string(_ index: Int) -> String { result.atIndex(index)?.stringValue ?? "" }
        func number(_ index: Int) -> Double { result.atIndex(index)?.doubleValue ?? 0 }

        let track = Track(
            id: string(2),
            title: string(3),
            artist: string(4),
            album: string(5),
            duration: number(6),
            player: player
        )
        let artworkURL = result.numberOfItems >= 8 ? URL(string: string(8)) : nil
        return Reading(track: track, playing: result.atIndex(1)?.booleanValue ?? false, position: number(7), artworkURL: artworkURL)
    }

    private func apply(_ reading: Reading?) {
        let changed = reading?.track != track
        track = reading?.track
        isPlaying = reading?.playing ?? false
        position = reading?.position ?? 0
        positionDate = Date()
        if changed {
            artwork = nil
            if let reading { loadArtwork(for: reading) }
        }
        schedule()
    }

    private func schedule() {
        timer?.invalidate()
        // Poll often while playing to keep lyrics in sync, rarely otherwise.
        let interval: TimeInterval = isPlaying ? 1 : 5
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.poll()
        }
    }

    private func loadArtwork(for reading: Reading) {
        let id = reading.track.id
        if let url = reading.artworkURL {
            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async { if self?.track?.id == id { self?.artwork = image } }
            }.resume()
            return
        }
        guard reading.track.player == .music else { return }
        let track = reading.track
        queue.async { [weak self] in
            let script = "tell application id \"com.apple.Music\" to get raw data of artwork 1 of current track"
            var error: NSDictionary?
            if let data = NSAppleScript(source: script)?.executeAndReturnError(&error).data, let image = NSImage(data: data) {
                DispatchQueue.main.async { if self?.track?.id == id { self?.artwork = image } }
            } else {
                // Songs streamed from Apple Music have no artwork of their own in Music's library.
                self?.loadCatalogueArtwork(for: track, attempt: 0)
            }
        }
    }

    /// Fetches a streamed song's artwork from Apple, by the link in Music's cached catalogue entry, trying
    /// again for a little while if Music hasn't cached the entry yet.
    private func loadCatalogueArtwork(for track: Track, attempt: Int) {
        guard let url = AppleMusicLyrics.artworkURL(title: track.title, duration: track.duration) else {
            if attempt < 5 {
                queue.asyncAfter(deadline: .now() + 2) { [weak self] in self?.loadCatalogueArtwork(for: track, attempt: attempt + 1) }
            }
            return
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let image = NSImage(data: data) else { return }
            DispatchQueue.main.async { if self?.track?.id == track.id { self?.artwork = image } }
        }.resume()
    }
}

extension Double {
    /// 125 → "2:05"
    var playbackTime: String {
        let seconds = Int(self.rounded(.down))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

#if DEBUG
extension NowPlayingStore {
    /// A song partway through, for the website's widget pictures.
    func loadSample(artwork image: NSImage?) {
        track = Track(id: "sample", title: "Low Orbit", artist: "Mira Vale", album: "Night Signals", duration: 226, player: .music)
        isPlaying = true
        artwork = image
        needsPermission = false
        position = 102
        positionDate = .now
    }
}
#endif

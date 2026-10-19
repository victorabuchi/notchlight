import Combine
import Foundation

/// Synced lyrics for the current track, timed against the playback position: Apple Music's own when Music
/// has fetched them, otherwise LRCLIB's, which also covers Spotify and songs from a station or autoplay.
final class LyricsStore: ObservableObject {
    static let shared = LyricsStore()

    struct Line: Identifiable, Equatable {
        let id: Int
        let begin: Double
        let end: Double
        let text: String
    }

    enum State: Equatable {
        case idle
        case loading
        case found
        /// Music has no lyrics for this song.
        case unavailable
        /// Lyrics only come from Apple Music.
        case otherPlayer
    }

    @Published private(set) var lines: [Line] = []
    @Published private(set) var state = State.idle

    private var subscription: AnyCancellable?
    /// Looks in Music's cache again whenever it changes, until Apple Music's lyrics turn up.
    private var watch: Timer?
    private var musicStamp: Date?
    /// The lines showing are Apple Music's own, so nothing else replaces them.
    private var fromApple = false
    private var cache: [String: [Line]] = [:]
    /// LRCLIB's lines for the current song, while Apple Music's may still arrive.
    private var fallback: Task<Void, Never>?
    private let queue = DispatchQueue(label: "LockWidgets.Lyrics")

    private init() {
        #if DEBUG
        if WidgetGallery.isRendering { return } // Sample data only.
        #endif
        subscription = NowPlayingStore.shared.$track
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] track in self?.load(track) }
    }

    /// Index of the line being sung at `position`; nil before the first line and during instrumental breaks.
    func currentIndex(at position: Double) -> Int? {
        guard let index = lines.lastIndex(where: { $0.begin <= position + 0.15 }) else { return nil }
        let line = lines[index]
        let nextBegin = index + 1 < lines.count ? lines[index + 1].begin : .infinity
        // A long gap after a line has ended is a break, as Music shows it.
        if position > line.end + 0.6, nextBegin - line.end > 4 { return nil }
        return index
    }

    private func load(_ track: NowPlayingStore.Track?) {
        watch?.invalidate()
        fallback?.cancel()
        fromApple = false
        guard let track else {
            lines = []
            state = .idle
            return
        }
        let key = track.id
        if let cached = cache[key] {
            lines = cached
            state = .found
            return
        }
        lines = []
        state = .loading
        guard track.player == .music else {
            // Spotify has no Apple Music lyrics to wait for.
            askLRCLib(track, key: key, after: 0)
            return
        }
        // Music fetches a song's lyrics when it shows them, which may be well into the song, so look now,
        // ask LRCLIB in case Music never does, and look again each time Music's cache changes.
        lookInMusic(track, key: key)
        askLRCLib(track, key: key, after: 2.5)
        musicStamp = AppleMusicLyrics.cacheChanged
        watch = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] timer in
            guard let self, NowPlayingStore.shared.track?.id == key, !fromApple else {
                timer.invalidate()
                return
            }
            let changed = AppleMusicLyrics.cacheChanged
            guard changed != musicStamp else { return }
            musicStamp = changed
            lookInMusic(track, key: key)
        }
    }

    /// LRCLIB's lyrics, shown unless Apple Music's are already here, after a moment for Music to answer first.
    private func askLRCLib(_ track: NowPlayingStore.Track, key: String, after delay: Double) {
        fallback = Task { [weak self] in
            if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
            guard !Task.isCancelled else { return }
            let found = await LRCLib.lyrics(for: track)
            await MainActor.run {
                guard let self, !Task.isCancelled, NowPlayingStore.shared.track?.id == key, !self.fromApple else { return }
                if let found {
                    self.show(found, key: key, keep: false)
                } else if self.state != .found {
                    self.state = .unavailable
                }
            }
        }
    }

    private func show(_ found: [AppleMusicLyrics.Line], key: String, keep: Bool) {
        let lines = found.enumerated().map { Line(id: $0.offset, begin: $0.element.begin, end: $0.element.end, text: $0.element.text) }
        // Apple Music's lines are kept for the song; LRCLIB's stay only until Apple's arrive.
        if keep { cache[key] = lines }
        self.lines = lines
        state = .found
    }

    /// Apple Music's own lyrics from Music's cache. They win, even over LRCLIB's already showing.
    private func lookInMusic(_ track: NowPlayingStore.Track, key: String) {
        queue.async { [weak self] in
            let found = AppleMusicLyrics.lyrics(title: track.title, artist: track.artist, duration: track.duration)
            DispatchQueue.main.async {
                guard let self, let found, NowPlayingStore.shared.track?.id == key, !self.fromApple else { return }
                self.fromApple = true
                self.fallback?.cancel()
                self.watch?.invalidate()
                self.show(found, key: key, keep: true)
            }
        }
    }
}

#if DEBUG
extension LyricsStore {
    /// Lines for the sample song, on its second line.
    func loadSample() {
        let texts = ["Neon on the window, rain on the road", "City lights are spelling out your name", "We drove until the morning found us", "Hold the moment, let the record play", "Every window glowing like a sign"]
        lines = texts.enumerated().map { index, text in Line(id: index, begin: 92 + Double(index) * 6, end: 97.5 + Double(index) * 6, text: text) }
        state = .found
    }
}
#endif

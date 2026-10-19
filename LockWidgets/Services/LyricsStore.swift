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
    private var retry: Timer?
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
        retry?.invalidate()
        fallback?.cancel()
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
            askLRCLib(track, key: key, finalAnswer: true)
            return
        }
        attempt(track, key: key, remaining: 10)
    }

    /// LRCLIB's lyrics, shown unless Apple Music's are already here. When it's the last source, no lyrics
    /// means the song has none.
    private func askLRCLib(_ track: NowPlayingStore.Track, key: String, finalAnswer: Bool) {
        fallback = Task { [weak self] in
            let found = await LRCLib.lyrics(for: track)
            await MainActor.run {
                guard let self, !Task.isCancelled, NowPlayingStore.shared.track?.id == key, self.state != .found else { return }
                if let found {
                    self.show(found, key: key, keep: false)
                } else if finalAnswer {
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

    /// Music fetches lyrics a moment after a song starts, so look a few times before giving up.
    private func attempt(_ track: NowPlayingStore.Track, key: String, remaining: Int) {
        queue.async { [weak self] in
            let found = AppleMusicLyrics.lyrics(title: track.title, artist: track.artist, duration: track.duration)
            DispatchQueue.main.async {
                guard let self, NowPlayingStore.shared.track?.id == key else { return }
                if let found {
                    // Apple Music's own lyrics win, even over LRCLIB's already showing.
                    self.fallback?.cancel()
                    self.show(found, key: key, keep: true)
                } else if remaining > 0 {
                    // After the first look, ask LRCLIB too, in case Music never fetches any.
                    if remaining == 9 { self.askLRCLib(track, key: key, finalAnswer: false) }
                    self.retry = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
                        self.attempt(track, key: key, remaining: remaining - 1)
                    }
                } else if self.state != .found {
                    self.state = .unavailable
                }
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

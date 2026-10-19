import SwiftUI

struct LyricsWidget: View {
    let instance: WidgetInstance
    @ObservedObject private var music = NowPlayingStore.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @AppStorage(SettingsKey.hideMusicWhenIdle) private var hideWhenIdle = true
    @Environment(\.isWidgetPreview) private var isPreview

    var body: some View {
        if let track = music.track {
            WidgetCard(size: instance.size, title: "\(track.title) · \(track.artist)", symbol: "quote.bubble") {
                content
            }
        } else if !hideWhenIdle || isPreview {
            WidgetCard(size: instance.size, title: "Lyrics", symbol: "quote.bubble") {
                WidgetPlaceholder(symbol: "music.note", message: "Play a song in Music or Spotify.")
            }
        }
    }

    private var fontSize: CGFloat {
        switch instance.size {
        case .large: 22
        case .wide: 20
        default: 17
        }
    }

    /// Lines after the current one that fit the widget.
    private var upcomingLines: Int {
        instance.size == .large ? 5 : 1
    }

    @ViewBuilder
    private var content: some View {
        switch lyrics.state {
        case .found:
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                lines(current: lyrics.currentIndex(at: music.position(at: context.date)))
            }
        case .loading, .idle:
            WidgetPlaceholder(symbol: "ellipsis", message: "Getting lyrics from Apple Music…")
        case .unavailable:
            WidgetPlaceholder(symbol: "quote.bubble", message: "No synced lyrics for this song.")
        case .otherPlayer:
            WidgetPlaceholder(symbol: "music.note", message: "Lyrics come from Apple Music.")
        }
    }

    private func lines(current: Int?) -> some View {
        let all = lyrics.lines
        guard !all.isEmpty else { return AnyView(EmptyView()) }
        // Between lines (an instrumental break) nothing is lit, like in Music.
        let index = current ?? -1
        let before = instance.size == .medium ? 0 : 1
        let window = all[max(index - before, 0) ..< min(index + 1 + upcomingLines, all.count)]

        // Keyed by line so a change slides lines up instead of swapping text in place.
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            ForEach(window) { item in
                // Same font for every line so nothing re-wraps mid-animation; only brightness changes.
                Text(item.text.isEmpty ? "♪" : item.text)
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(item.id == index ? 1 : item.id < index ? 0.25 : 0.4))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: index))
    }
}

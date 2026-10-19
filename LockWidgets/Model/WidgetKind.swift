import SwiftUI

/// Footprint of a widget on the lock screen, in screen points.
enum WidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, wide, ultraWide, large

    var id: String { rawValue }

    var title: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .wide: "Wide"
        case .ultraWide: "Ultra Wide"
        case .large: "Large"
        }
    }

    var points: CGSize {
        switch self {
        case .small: CGSize(width: 164, height: 164)
        case .medium: CGSize(width: 344, height: 164)
        case .wide: CGSize(width: 524, height: 164)
        case .ultraWide: CGSize(width: 704, height: 164)
        case .large: CGSize(width: 344, height: 344)
        }
    }
}

/// One look a widget can take, offered in the sizes it supports.
struct WidgetStyle: Identifiable, Hashable {
    let id: String
    let name: String
    let summary: String
    let sizes: [WidgetSize]
}

enum WidgetCategory: String, CaseIterable {
    case essentials = "Essentials"
    case music = "Music"
    case productivity = "Productivity"
    case information = "Information"
    case briefings = "Briefings"
}

/// Everything that describes a widget kind, kept together so adding one is a single edit.
struct WidgetMeta {
    let title: String
    let symbol: String
    let color: Color
    let summary: String
    let category: WidgetCategory
    let styles: [WidgetStyle]
}

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    // Sidebar order.
    case weather, earth, location, news, stocks, nowPlaying, musicCard, photos, lyrics, calendar, clock, countdown, pomodoro, stopwatch, reminders, favorites, activity, battery, system, dailyBrief, stickyNote

    var id: String { rawValue }
    var title: String { meta.title }
    var symbol: String { meta.symbol }
    var color: Color { meta.color }
    var summary: String { meta.summary }
    var category: WidgetCategory { meta.category }
    var styles: [WidgetStyle] { meta.styles }

    var meta: WidgetMeta {
        switch self {
        case .weather: WidgetMeta(
            title: "Weather", symbol: "cloud.sun", color: .cyan,
            summary: "Current conditions and the forecast ahead.", category: .essentials,
            styles: [
                WidgetStyle(id: "current", name: "Current", summary: "Conditions right now.", sizes: [.small, .medium]),
                WidgetStyle(id: "hourly", name: "Hourly", summary: "Now and the next few hours.", sizes: [.medium, .wide, .ultraWide]),
                WidgetStyle(id: "daily", name: "Five Day", summary: "The week ahead at a glance.", sizes: [.wide, .large]),
            ]
        )
        case .earth: WidgetMeta(
            title: "Earth", symbol: "globe.europe.africa.fill", color: .blue,
            summary: "The planet as it is now, with day and night, centred on you.", category: .information,
            styles: [
                WidgetStyle(id: "globe", name: "Globe", summary: "Live daylight across the world.", sizes: [.small, .medium, .large]),
            ]
        )
        case .location: WidgetMeta(
            title: "Location", symbol: "location.fill", color: .blue,
            summary: "A map of where you are, with the name of the place.", category: .information,
            styles: [
                WidgetStyle(id: "map", name: "Map", summary: "Your surroundings, with a dot where you are.", sizes: [.small, .medium, .wide, .large]),
                WidgetStyle(id: "satellite", name: "Satellite", summary: "Where you are, seen from above.", sizes: [.small, .medium, .wide, .large]),
                WidgetStyle(id: "hybrid", name: "Hybrid", summary: "Satellite photos with roads and place names.", sizes: [.small, .medium, .wide, .large]),
            ]
        )
        case .news: WidgetMeta(
            title: "News", symbol: "newspaper", color: .red,
            summary: "The latest headlines from a source you pick.", category: .information,
            styles: [
                WidgetStyle(id: "headlines", name: "Headlines", summary: "The newest stories, with how long ago they broke.", sizes: [.medium, .wide, .large]),
            ]
        )
        case .stocks: WidgetMeta(
            title: "Stock Ticker", symbol: "chart.line.uptrend.xyaxis", color: .mint,
            summary: "Prices and today's moves for stocks, ETFs, crypto and currency pairs.", category: .information,
            styles: [
                WidgetStyle(id: "watchlist", name: "Watchlist", summary: "Your symbols with price and change.", sizes: [.medium, .wide, .large]),
                WidgetStyle(id: "spotlight", name: "Spotlight", summary: "One symbol and its chart for the day.", sizes: [.small, .medium]),
            ]
        )
        case .nowPlaying: WidgetMeta(
            title: "Now Playing", symbol: "music.note", color: .pink,
            summary: "The song playing in Apple Music or Spotify.", category: .music,
            styles: [
                WidgetStyle(id: "player", name: "Player", summary: "Artwork, song and progress.", sizes: [.medium, .wide]),
                WidgetStyle(id: "artwork", name: "Artwork", summary: "Album art front and centre.", sizes: [.small, .large]),
            ]
        )
        case .musicCard: WidgetMeta(
            title: "Music Card", symbol: "play.rectangle.fill", color: .pink,
            summary: "The song in a glass card, like the iPhone's lock screen. It appears only while a song is playing.", category: .music,
            styles: [
                WidgetStyle(id: "glass", name: "Glass", summary: "Artwork, song, progress and controls.", sizes: [.medium, .wide]),
            ]
        )
        case .photos: WidgetMeta(
            title: "Photos", symbol: "photo.on.rectangle", color: .indigo,
            summary: "Favourites, a folder, or photos you choose and arrange, changing through the day.", category: .information,
            styles: [
                WidgetStyle(id: "photo", name: "Photo", summary: "Edge to edge.", sizes: [.small, .medium, .large]),
                WidgetStyle(id: "framed", name: "Framed", summary: "A print with a white border and the date.", sizes: [.small, .large]),
            ]
        )
        case .lyrics: WidgetMeta(
            title: "Live Lyrics", symbol: "quote.bubble", color: .purple,
            summary: "Time-synced lyrics that follow the song.", category: .music,
            styles: [
                WidgetStyle(id: "lyrics", name: "Lyrics", summary: "Follow along line by line.", sizes: [.medium, .wide, .large]),
            ]
        )
        case .calendar: WidgetMeta(
            title: "Calendar", symbol: "calendar", color: .red,
            summary: "Today's date, your month and what's next.", category: .essentials,
            styles: [
                WidgetStyle(id: "date", name: "Date", summary: "Today's date, big and bold.", sizes: [.small, .medium]),
                WidgetStyle(id: "monthly", name: "Monthly", summary: "The full month with today highlighted.", sizes: [.small, .medium, .large]),
                WidgetStyle(id: "upNext", name: "Up Next", summary: "Your next events with times and colours.", sizes: [.small, .medium, .wide, .large]),
            ]
        )
        case .clock: WidgetMeta(
            title: "Clock", symbol: "clock", color: .orange,
            summary: "Digital, analog and world clocks.", category: .essentials,
            styles: [
                WidgetStyle(id: "digital", name: "Digital", summary: "The time in large type, with the date.", sizes: [.small, .medium, .wide]),
                WidgetStyle(id: "analog", name: "Analog", summary: "A classic clock face.", sizes: [.small, .medium]),
                WidgetStyle(id: "world", name: "World Clock", summary: "The time in the cities you care about.", sizes: [.medium, .wide, .ultraWide]),
            ]
        )
        case .countdown: WidgetMeta(
            title: "Countdown", symbol: "hourglass", color: Color(red: 0.95, green: 0.4, blue: 0.35),
            summary: "Days, hours and minutes until something you're waiting for.", category: .productivity,
            styles: [
                WidgetStyle(id: "days", name: "Days", summary: "A big day count.", sizes: [.small, .medium]),
                WidgetStyle(id: "units", name: "Flip", summary: "Days, hours, minutes and seconds.", sizes: [.medium, .wide]),
            ]
        )
        case .pomodoro: WidgetMeta(
            title: "Pomodoro", symbol: "timer", color: Color(red: 0.98, green: 0.45, blue: 0.3),
            summary: "Focus sessions with breaks in between.", category: .productivity,
            styles: [
                WidgetStyle(id: "ring", name: "Ring", summary: "Time left in the current session.", sizes: [.small, .medium]),
            ]
        )
        case .stopwatch: WidgetMeta(
            title: "Stopwatch", symbol: "stopwatch", color: .teal,
            summary: "Time anything. Start and stop it from the menu bar.", category: .productivity,
            styles: [
                WidgetStyle(id: "digits", name: "Digits", summary: "Elapsed time in large type.", sizes: [.small, .medium]),
            ]
        )
        case .reminders: WidgetMeta(
            title: "Reminders", symbol: "checklist", color: .blue,
            summary: "Your open reminders, soonest first.", category: .productivity,
            styles: [
                WidgetStyle(id: "list", name: "List", summary: "What's left to do.", sizes: [.small, .medium, .large]),
            ]
        )
        case .favorites: WidgetMeta(
            title: "Favourite Apps", symbol: "square.grid.2x2.fill", color: .orange,
            summary: "The apps you use most, a click away.", category: .productivity,
            styles: [
                WidgetStyle(id: "grid", name: "Grid", summary: "Your favourite apps with their names.", sizes: [.small, .medium, .wide, .large]),
                WidgetStyle(id: "single", name: "One App", summary: "One app of your choice, as big as a home screen icon.", sizes: [.small]),
                WidgetStyle(id: "pair", name: "Two Apps", summary: "Two apps of your choice, side by side.", sizes: [.small]),
            ]
        )
        case .activity: WidgetMeta(
            title: "Recent Activity", symbol: "chart.bar.fill", color: .indigo,
            summary: "How long you've spent in each app today, hour by hour.", category: .productivity,
            styles: [
                WidgetStyle(id: "today", name: "Today", summary: "Total time, an hourly chart and your top apps.", sizes: [.medium, .wide, .large]),
            ]
        )
        case .battery: WidgetMeta(
            title: "Battery", symbol: "battery.75", color: .green,
            summary: "Charge level and time remaining.", category: .essentials,
            styles: [
                WidgetStyle(id: "ring", name: "Ring", summary: "A charge ring with the percentage.", sizes: [.small]),
                WidgetStyle(id: "bar", name: "Bar", summary: "Charge, status and time remaining.", sizes: [.medium, .wide]),
            ]
        )
        case .system: WidgetMeta(
            title: "System", symbol: "cpu", color: .purple,
            summary: "CPU, memory, network and disk at a glance.", category: .information,
            styles: [
                WidgetStyle(id: "gauges", name: "Gauges", summary: "CPU and memory rings.", sizes: [.small, .medium]),
                WidgetStyle(id: "list", name: "Monitor", summary: "Every metric with a live sparkline.", sizes: [.medium, .large]),
            ]
        )
        case .dailyBrief: WidgetMeta(
            title: "Daily Brief", symbol: "sun.horizon.fill", color: .orange,
            summary: "A greeting with your weather, next event, reminders and top story.", category: .briefings,
            styles: [
                WidgetStyle(id: "brief", name: "Brief", summary: "Your day in one card.", sizes: [.medium, .wide, .large]),
            ]
        )
        case .stickyNote: WidgetMeta(
            title: "Sticky Note", symbol: "note.text", color: .yellow,
            summary: "A note to yourself, right on the lock screen.", category: .productivity,
            styles: [
                WidgetStyle(id: "paper", name: "Paper", summary: "A coloured note.", sizes: [.small, .medium, .large]),
                WidgetStyle(id: "glass", name: "Glass", summary: "Matches your other widgets.", sizes: [.small, .medium, .large]),
            ]
        )
        }
    }

    /// Kinds listed under Widget Settings; sticky notes have their own page.
    static var settingsKinds: [WidgetKind] { allCases.filter { $0 != .stickyNote } }

    var defaultStyle: WidgetStyle { styles[0] }

    func style(_ id: String) -> WidgetStyle {
        styles.first { $0.id == id } ?? defaultStyle
    }

    /// An unplaced instance used for previews.
    func sample(style: String? = nil, size: WidgetSize? = nil) -> WidgetInstance {
        let style = self.style(style ?? defaultStyle.id)
        return WidgetInstance(kind: self, style: style.id, size: size ?? style.sizes[0], center: .zero)
    }
}

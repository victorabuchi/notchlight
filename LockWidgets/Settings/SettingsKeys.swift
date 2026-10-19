import SwiftUI

enum SettingsKey {
    static let showOnLockScreen = "showOnLockScreen"
    static let scale = "boardScale"
    static let cardStyle = "cardStyle"
    static let cornerRadius = "cardCornerRadius"
    static let use24Hour = "clockUse24Hour"
    static let showSeconds = "clockShowSeconds"
    static let worldClockZones = "clockWorldZones"
    static let weatherCity = "weatherCity"
    static let fahrenheit = "weatherFahrenheit"
    static let hideMusicWhenIdle = "musicHideWhenIdle"
    static let lyricsUpcomingLines = "lyricsUpcomingLines"
    static let calendarMaxEvents = "calendarMaxEvents"
    static let calendarIncludeTomorrow = "calendarIncludeTomorrow"
    static let studioBackground = "studioBackground"
    static let hasLaunched = "hasLaunched"
    static let islandEnabled = "islandEnabled"
    static let islandMusic = "islandMusic"
    static let islandLyrics = "islandLyrics"
    static let islandTimers = "islandTimers"
    static let islandHotspot = "islandHotspot"
    static let islandMeetings = "islandMeetings"
    static let islandBattery = "islandBattery"
    static let islandNotifications = "islandNotifications"
    static let islandCalendar = "islandCalendar"
    static let islandDevices = "islandDevices"
    static let islandHUD = "islandHUD"
    static let islandFocus = "islandFocus"
    static let islandLock = "islandLock"
    static let islandPrivacy = "islandPrivacy"
    static let islandTrips = "islandTrips"
    static let islandReminders = "islandReminders"
    static let islandHomeTime = "islandHomeTime"
    /// The time zone the island counts as home, as an identifier such as "Europe/Helsinki".
    static let homeTimeZone = "homeTimeZone"
    static let favoriteApps = "favoriteApps"

    // The notch: the island's behaviour, Light, the Tray and the drop area.
    static let islandHoverOpens = "islandHoverOpens"
    static let notchWidthAdjust = "notchWidthAdjust"
    static let notchHeightAdjust = "notchHeightAdjust"
    static let gestures = "gestures"
    static let gestureOpenClose = "gestureOpenClose"
    static let gestureMedia = "gestureMedia"
    static let gestureInvert = "gestureInvert"
    static let liquidGlass = "liquidGlass"
    static let liquidTint = "liquidTint"
    static let liquidClear = "liquidClear"
    static let lightEnabled = "lightEnabled"
    static let lightOnHover = "lightOnHover"
    /// The widgets Light shows, in order, as their names joined by commas.
    static let lightWidgets = "lightWidgets"
    static let lightNotes = "lightNotes"
    /// Light's note is kept in Apple Notes too.
    static let lightNotesSync = "lightNotesSync"
    /// "all" for every chosen widget side by side, or "music" for the song alone.
    static let lightShows = "lightShows"
    /// What a click on a live island opens: "light", or "app" for the app behind it.
    static let islandClick = "islandClick"
    static let trayOpensWithFiles = "trayOpensWithFiles"
    static let trayFiles = "trayFiles"
    static let dropArea = "dropArea"
    static let dropAirDrop = "dropAirDrop"

    /// A switch's value, or its default before the user has touched it.
    static func isOn(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }

    /// Follows the region (°F in the US) until the user picks a unit.
    static var defaultFahrenheit: Bool { Locale.current.measurementSystem == .us }
}

enum CardStyle: String, CaseIterable, Identifiable {
    case glass, frosted, solid, minimal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .glass: "Glass"
        case .frosted: "Frosted"
        case .solid: "Solid"
        case .minimal: "Minimal"
        }
    }

    var detail: String {
        switch self {
        case .glass: "See-through blur that picks up your wallpaper."
        case .frosted: "Heavier blur with a darker tint for busy wallpapers."
        case .solid: "Opaque dark cards."
        case .minimal: "No card at all, just text with a soft shadow."
        }
    }
}

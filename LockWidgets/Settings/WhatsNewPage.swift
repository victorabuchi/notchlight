import SwiftUI

struct WhatsNewPage: View {
    private struct Release {
        let version: String
        let summary: String
        let items: [(symbol: String, title: String, detail: String)]
    }

    private let releases = [
        Release(
            version: "1.4",
            summary: "Trips, to-dos and home time on the island, a new icon, and a 7-day free trial before you buy.",
            items: [
                ("key.fill", "Try it, then buy it once", "Everything is free for 7 days. A licence is one payment, with no subscription, for up to 3 of your Macs. Enter yours in Settings, under Licence."),
                ("bus.fill", "Trips", "A bus, train or flight from your calendar, or one you start from the menu bar: the time it leaves, then the time left on a blue line, as Maps shows a journey on the iPhone."),
                ("checklist", "To-dos", "Reminders due today wait in the circle beside the notch. Point at it to see them."),
                ("house.fill", "Home time", "In another time zone, the time back home waits in the circle, after a moment saying how far you are from home."),
                ("personalhotspot", "A calmer island", "The hotspot on its own sits in the circle, with the microphone, camera or recording dot beside it, and brightness shows only when you change it."),
                ("app.fill", "A new icon", "A framed screen with the notch, on Apple blue, with Dark, Clear and Tinted versions."),
            ]
        ),
        Release(
            version: "1.3",
            summary: "LockWidgets is now Notchlight, with a new icon, automatic updates and four new widgets.",
            items: [
                ("sparkles", "A new name", "LockWidgets is now Notchlight. Your widgets, settings and permissions carry over."),
                ("map", "Location", "A map of where you are, with the name of the place."),
                ("play.rectangle.fill", "Music Card", "The song in a glass card, like the iPhone's lock screen. It appears only while music plays."),
                ("square.grid.2x2.fill", "Favourite Apps", "Your apps in a grid, or one or two at a time anywhere you like."),
                ("chart.bar.fill", "Recent Activity", "How long you've spent in each app today, hour by hour. It never leaves your Mac."),
                ("arrow.down.circle", "Automatic updates", "Notchlight checks for a new version once a day and asks before installing it. Check any time from the menu bar."),
                ("shippingbox", "Install with Homebrew", "brew install --cask victorabuchi/tap/notchlight"),
            ]
        ),
        Release(
            version: "1.2",
            summary: "A Dynamic Island for your MacBook's notch: the song, your calls, notifications and more, like the iPhone.",
            items: [
                ("capsule.fill", "Dynamic Island", "Live activities beside the notch. Point at the island to see more; click it to open the app."),
                ("music.note", "Now Playing in the notch", "Artwork and a live waveform, with the Apple Music lyric, progress and controls when you point at it."),
                ("bell.badge", "Notifications", "Every app's notifications drop down from the notch as they arrive. Needs Full Disk Access."),
                ("video", "Calls and meetings", "Zoom, FaceTime, Teams, Google Meet and calls in your browser, with how long you've been on."),
                ("personalhotspot", "Hotspot, timers and alerts", "Personal Hotspot, the Pomodoro and Stopwatch, charging, AirPods, volume, brightness, Focus and upcoming events."),
                ("lock.display", "On the lock screen too", "The island stays at the notch while your Mac is locked."),
            ]
        ),
        Release(
            version: "1.1",
            summary: "Place widgets anywhere, in the size and style you like, with ten new widgets to choose from.",
            items: [
                ("quote.bubble", "Apple Music lyrics", "Live Lyrics now shows Apple Music's own synced lyrics, timed exactly as in Music."),
                ("rectangle.3.group", "Layout Studio", "Drag widgets anywhere on the lock screen. Select one to change its size, its style or to remove it."),
                ("square.grid.2x2", "Layout Gallery", "Seven ready-made layouts, from After Hours to Mission Control."),
                ("plus.rectangle.on.rectangle", "Widget sizes and styles", "Small, Medium, Wide, Ultra Wide and Large, with live previews when you add a widget."),
                ("sparkles", "Ten new widgets", "Earth, News, Stock Ticker, Photos, Countdown, Pomodoro, Stopwatch, Reminders, System and Daily Brief."),
                ("note.text", "Sticky Notes", "Leave yourself a note on the lock screen in five paper colours."),
                ("menubar.rectangle", "A fuller menu bar", "Open any page, hide widgets, and control the Pomodoro and Stopwatch."),
                ("figure.wave", "Setup Guide", "A short introduction to get started, available any time from General."),
            ]
        ),
        Release(
            version: "1.0",
            summary: "The first release.",
            items: [
                ("lock.display", "Widgets on the lock screen", "Clock, Weather, Calendar, Now Playing, Live Lyrics and Battery."),
                ("quote.bubble", "Live Lyrics", "Time-synced lyrics on the lock screen."),
                ("checkmark.seal", "Signed and notarized", "Installs and opens like any app from the App Store."),
            ]
        ),
    ]

    private var installed: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 18) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What's New").font(.system(size: 26, weight: .bold))
                        Text("What's changed in recent Notchlight updates.").foregroundStyle(.secondary)
                        Label("Installed version: \(installed)", systemImage: "checkmark.circle.fill")
                            .font(.callout.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                    }
                }
                ForEach(releases, id: \.version) { release in
                    Divider()
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Notchlight \(release.version)").font(.system(size: 20, weight: .bold))
                            Text(release.summary).foregroundStyle(.secondary)
                        }
                        ForEach(release.items, id: \.title) { item in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: item.symbol)
                                    .font(.title3)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.headline)
                                    Text(item.detail).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

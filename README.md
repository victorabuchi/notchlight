# Notchlight

Widgets on your Mac's lock screen and a Dynamic Island around the notch.

Website: [notchlight.com](https://notchlight.com)

Notchlight puts live widgets on your Mac's lock screen: the weather, your next meeting, the song playing with its synced lyrics, your notes, a live globe and more. Glance at your Mac without unlocking it. Arrange the widgets wherever you like in Layout Studio, start from a ready-made layout in the Gallery, and pick the look that suits your wallpaper.

It runs from the menu bar. When you lock your Mac, it draws your widgets in a layer above the lock screen using [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow), and removes them when you sign back in.

On a MacBook with a notch, Notchlight also turns the notch into a Dynamic Island, like the iPhone's: the song that's playing, your calls, notifications and system alerts, on the desktop and on the lock screen. Click the notch for Light: your music, a mirror, calendar, notes, timers and to-dos side by side, and a Tray for files you drag to the notch.

## Features

- **Dynamic Island** around the MacBook notch, with Now Playing, calls, notifications, Personal Hotspot, timers and system alerts
- **21 widgets** in Small, Medium, Wide, Ultra Wide and Large sizes, most with several styles
- **Layout Studio**: drag widgets anywhere on a life-size preview of your lock screen, with a warning when one covers the system clock or login area
- **Layout Gallery**: seven ready-made layouts to start from
- **Light**: click or swipe down on the notch for the song, a camera mirror, your calendar, notes (kept in Apple Notes), timers, to-dos from Reminders, weather, battery or your Shortcuts, in the order you choose
- **The Tray**: drag files to the notch to keep them close, or drop them on AirDrop
- **Synced lyrics**: Apple Music's own time-synced lyrics when Music has them, otherwise LRCLIB's, in Apple Music and Spotify
- **Appearance**: Glass, Frosted, Solid or Minimal cards, with adjustable corner radius
- **Sticky Notes**: notes to yourself in five paper colours
- **Menu bar controls**: hide widgets, preview them on the desktop, and run the Pomodoro and Stopwatch
- **Setup Guide** on first launch

## Widgets

| Widget | Styles | Data |
| --- | --- | --- |
| Weather | Current, Hourly, Five Day | [Open-Meteo](https://open-meteo.com) |
| Earth | Globe with live day and night | Apple Maps satellite imagery |
| Location | Map | Apple Maps, at the same place as Weather |
| News | Headlines | Any RSS or Atom feed |
| Stock Ticker | Watchlist, Spotlight | Yahoo Finance |
| Now Playing | Player, Artwork | Apple Music and Spotify |
| Music Card | Glass, shown only while a song plays | Apple Music and Spotify |
| Photos | Photo, Framed | Photos library or a folder |
| Live Lyrics | Lyrics | Apple Music, from Music on your Mac, or LRCLIB |
| Calendar | Date, Monthly, Up Next | Your calendars |
| Clock | Digital, Analog, World Clock | System time |
| Countdown | Days, Flip | A date you choose |
| Pomodoro | Ring | Built in |
| Stopwatch | Digits | Built in |
| Reminders | List | Your reminders |
| Favourite Apps | Grid, One App, Two Apps | Apps you choose |
| Recent Activity | Today | Time in each app, counted on your Mac |
| Battery | Ring, Bar | System |
| System | Gauges, Monitor | CPU, memory, network, disk |
| Daily Brief | Brief | Weather, calendar, reminders, news |
| Sticky Note | Paper, Glass | Your text |

## Dynamic Island

With nothing going on, the island is exactly your notch. When something is live, it shows beside the notch at the notch's height, and a second live activity waits in its own circle on the right.

| Activity | Beside the notch | When you point at it |
| --- | --- | --- |
| Now Playing | Artwork and a live waveform | Song, Apple Music lyric, progress and controls |
| Calls and meetings | Call icon and time | App, mic and camera, Zoom controls |
| Personal Hotspot | Hotspot icon | The iPhone you're connected to |
| Pomodoro and Stopwatch | Timer and time left | Pause and skip or reset |
| Trips | Bus, train or plane and the time left | Where to, when you arrive and the journey so far |
| To-dos | Reminders due today, in the circle | The next three |
| Home time | In another time zone, home's time in the circle | Here and home, and the difference |

Notifications from every app, upcoming events, charging, low battery, AirPods and other Bluetooth devices, volume, brightness and Focus drop down from the notch for a few seconds.

Point at the island to see more. Click it to open the app behind it: Music or Spotify for a song, Wi-Fi settings for the hotspot, or the app that sent a notification. Calls are found by the app using the microphone, including Zoom, Google Meet and Teams in Chrome, Firefox and Safari. On Macs without a notch, the island appears only while something is live.

## Install

1. Download `Notchlight-<version>.dmg` from [Releases](../../releases).
2. Open it and drag **Notchlight** into **Applications**.
3. Open Notchlight. The Setup Guide runs on first launch. Afterwards, open the app again or use its menu bar icon.
4. Lock your Mac with **Control + Command + Q** to see your widgets.

Or install it with [Homebrew](https://brew.sh):

```sh
brew install --cask victorabuchi/tap/notchlight
```

Notchlight is free for 7 days. After that, a licence is $14.99, paid once, for up to 3 of your Macs: buy it at [notchlight.com](https://notchlight.com) and enter the key in **Settings → Licence**.

Requires macOS 15 or later. Builds are signed with a Developer ID and notarized by Apple. Notchlight checks for updates once a day and asks before installing one; choose **Check for Updates…** in its menu to look now.

## Permissions

Notchlight asks only when a widget needs something:

- **Calendar** for Calendar and Daily Brief
- **Reminders** for Reminders
- **Location** for local weather (not needed if you set a city)
- **Photos** for the Photos widget (not needed if you pick a folder)
- **Automation** to read the current song from Music or Spotify. Notchlight only talks to a player that is already open.
- **Full Disk Access** for notifications and Focus on the Dynamic Island. macOS keeps both in protected files; the Setup Guide links to the setting.
- **Accessibility** (optional) to name a call in your browser, such as Zoom or Google Meet, from the window title.

## Privacy

Notchlight collects no data. Weather, news and prices come straight from their public sources. Lyrics are read from Apple Music on your Mac: when Music fetches a song's lyrics from Apple, Notchlight reads Music's local copy. For other songs and for Spotify, synced lyrics come from LRCLIB (lrclib.net), which receives the song's title, artist, album and length. A streamed song's artwork comes from Apple, by the link in Music's copy or from Apple's iTunes Search. Light's note is also kept in Apple Notes, and the Mirror shows the camera only while it's on. Notifications are read from macOS's own notification database on your Mac and never leave it. Recent Activity notes which app is in front to add up today's time, and keeps that in a file on your Mac. Nothing is sent anywhere else. The full policy is at [notchlight.com/privacy](https://notchlight.com/privacy/).

## How lyrics work

Apple doesn't offer Apple Music lyrics to other apps. Music does keep the lyrics it downloads, Apple's time-synced TTML, in its cache at `~/Library/Caches/com.apple.Music`. Notchlight finds the entry for the playing song by title and length and highlights each line at Apple's timestamps against Music's playback position. Music fetches a song's lyrics when it shows them, so Notchlight looks again whenever Music's cache changes. Until then, and for Spotify, it asks LRCLIB for synced lyrics. If neither has any, the widget says so.

## Development

The Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen generate
open LockWidgets.xcodeproj
```

Run `xcodegen generate` again after adding files outside Xcode.

| Folder | Contents |
| --- | --- |
| `LockWidgets/Model` | Widget kinds, styles and sizes; the saved layout and gallery presets |
| `LockWidgets/Widgets` | One SwiftUI view per widget, plus the shared card |
| `LockWidgets/Island` | The Dynamic Island: its window, state and the view for each activity |
| `LockWidgets/Services` | Data sources: weather, calendar, music, lyrics, system and so on |
| `LockWidgets/Settings` | The settings window, Layout Studio, Gallery and Setup Guide |
| `scripts` | Install, release and widget gallery scripts, and the renderers for the website's icon and link preview |

Debug builds accept launch arguments for screenshots, such as `-settingsPage studio` or `-previewAtLaunch YES`. `scripts/widget-gallery.sh <folder>` draws every widget, in each style and size, with sample data to PNG files for the website; it reads none of your data and changes no settings.

### Releasing

```sh
scripts/release.sh            # signed DMG in dist/
scripts/release.sh --publish  # also the GitHub release, its update feed and the Homebrew cask
```

Before each release, test on the current macOS and, from June each year, on the new macOS beta. The lock screen layer, notifications, Apple Music lyrics and the screen recording dot rely on parts of macOS that Apple can change in any update, so lock the Mac with widgets showing, play a song, get a notification and start a screen recording.

Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml` first; installed copies only update when the build number goes up. The script notarizes the DMG when a keychain profile named `lockwidgets-notary` exists:

```sh
xcrun notarytool store-credentials lockwidgets-notary --apple-id <apple-id> --team-id 4T4AXT6P7X
```

Updates reach installed copies through [Sparkle](https://sparkle-project.org). Each release uploads an `appcast.xml` describing the new version, and its download is signed with the EdDSA key in `~/.config/notchlight/sparkle-ed25519.key`, whose public half is `SUPublicEDKey` in `project.yml`. Keep a backup of that key: without it, installed copies won't accept new versions.

The app icon is `LockWidgets/AppIcon.icon`, an Icon Composer document (open it in Icon Composer, which comes with Xcode, to change it); macOS draws its Dark, Clear and Tinted versions from it. `scripts/render-icon.sh` renders the website's copies.

### Website

The website is `docs/index.html`, with the Privacy and Terms pages in `docs/privacy` and `docs/terms`. Render serves it at [notchlight.com](https://notchlight.com) from `render.yaml` and redeploys whenever something in `docs` changes on `main`. `scripts/og-image.sh` redraws its link preview from the page.

## Credits

- [SkyLightWindow](https://github.com/Lakr233/SkyLightWindow) by Lakr Aream, for drawing above the lock screen
- [Sparkle](https://sparkle-project.org), for updates
- [Open-Meteo](https://open-meteo.com) for weather

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://notchlight.com/assets/icon-dark.png?v=3">
    <img src="https://notchlight.com/assets/icon.png?v=3" width="96" height="96" alt="">
  </picture>
</p>

<h1 align="center">Notchlight</h1>

<p align="center"><b>Widgets on your lock screen. An island at your notch.</b></p>

<p align="center">
  <a href="https://github.com/victorabuchi/notchlight/releases/latest/download/Notchlight.dmg"><b>Download Notchlight</b></a> ·
  <a href="https://notchlight.com">Website</a> ·
  <a href="https://notchlight.com/#plans">Pricing</a> ·
  <a href="https://github.com/victorabuchi/notchlight/releases">All versions</a>
</p>

Notchlight puts live widgets on your Mac's lock screen: the weather, your next meeting, the song playing with its synced lyrics, your notes, a live globe and more, so you can glance at your Mac without unlocking it. On a MacBook it turns the notch into a Dynamic Island, like the iPhone's, and a click on the notch opens Light: your music, a mirror, your calendar, notes, timers and to-dos side by side, with a Tray for your files.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://notchlight.com/assets/try/lock-dark.webp">
  <img src="https://notchlight.com/assets/try/lock-light.webp" alt="Notchlight on a Mac's lock screen: widgets around the time, with a song at the notch">
</picture>

## Install

1. Download [Notchlight.dmg](https://github.com/victorabuchi/notchlight/releases/latest/download/Notchlight.dmg).
2. Open it and drag Notchlight into Applications.
3. Open Notchlight. The first time, macOS asks whether you're sure. Click Open.

Or with Homebrew:

```
brew install --cask victorabuchi/tap/notchlight
```

Every feature is free for 7 days. After that, Notchlight is $14.99, paid once, for up to 3 of your Macs; buy it at [notchlight.com](https://notchlight.com/#plans). It needs macOS Sequoia 15 or later, it's signed with a Developer ID and notarized by Apple, and it updates itself.

## What's inside

| | |
| --- | --- |
| Lock screen widgets | 21 widgets, from Weather, Calendar and Live Lyrics to Photos, Location and Recent Activity, in several sizes and styles |
| Layout Studio | Drag widgets anywhere on a life-size preview of your lock screen, or start from a ready-made layout |
| Dynamic Island | The song that's playing, calls, timers, trips, notifications and system alerts, beside the notch |
| Light | Click the notch for the song, a camera mirror, your calendar, notes, timers and to-dos, in the order you choose |
| The Tray | Drag files to the notch to keep them close, or drop them on AirDrop |
| Synced lyrics | Line by line, from Apple Music's own lyrics or LRCLIB, in Apple Music and Spotify |

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://notchlight.com/assets/try/island-dark.webp">
  <img src="https://notchlight.com/assets/try/island-light.webp" alt="The Dynamic Island showing a song beside the notch, and opened with its lyric and controls">
</picture>

## Privacy

Notchlight has no account, no analytics in the app and no tracking, and what it shows stays on your Mac. The [privacy policy](https://notchlight.com/privacy/) lists the few services its widgets talk to, such as Open-Meteo for the weather.

## Help

Something not right? [Open an issue](https://github.com/victorabuchi/notchlight/issues/new) with what you saw, your Mac's model and its macOS version, or write to support@notchlight.com.

## This repository

It holds Notchlight's downloads, in [Releases](https://github.com/victorabuchi/notchlight/releases), and NotchShape, the small Swift package that draws the curved notch shape Notchlight's island, Light and Tray are made of. NotchShape is free to use under the MIT License; Notchlight itself is not open source, and its source code is private.

Apple, Mac, MacBook, macOS and Apple Music are trademarks of Apple Inc.; Spotify is a trademark of Spotify AB. Notchlight isn't affiliated with or endorsed by either.

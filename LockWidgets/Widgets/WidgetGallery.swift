#if DEBUG
import AppKit
import SwiftUI

/// Test builds only: draws every widget, in each style and size, with sample data to PNG files for the
/// website, then quits before any window, island or menu bar icon appears. The stores skip their live
/// updates while it runs, so it reads none of your data and talks to no app; see scripts/widget-gallery.sh.
enum WidgetGallery {
    /// Where to write the pictures, from the `-renderWidgets` launch argument.
    static let folder = UserDefaults.standard.string(forKey: "renderWidgets").map { URL(fileURLWithPath: $0, isDirectory: true) }
    static var isRendering: Bool { folder != nil }

    @MainActor
    static func run(into folder: URL) -> Never {
        let samples = UserDefaults.standard.string(forKey: "gallerySamples").map { URL(fileURLWithPath: $0, isDirectory: true) }
        let cover = samples.flatMap { NSImage(contentsOf: $0.appendingPathComponent("cover.jpg")) }
        let photo = samples.flatMap { NSImage(contentsOf: $0.appendingPathComponent("photo.jpg")) }

        func loadSamples() {
            WeatherStore.shared.loadSample()
            CalendarStore.shared.loadSample()
            NowPlayingStore.shared.loadSample(artwork: cover)
            LyricsStore.shared.loadSample()
            BatteryMonitor.shared.loadSample()
            SystemMonitor.shared.loadSample()
            TimerStore.shared.loadSample()
            RemindersStore.shared.loadSample()
            NewsStore.shared.loadSample()
            StocksStore.shared.loadSample()
            PhotosStore.shared.loadSample(photo)
            ActivityTracker.shared.loadSample()
        }

        let instances = instances()
        loadSamples()
        // A first pass asks MapKit for the maps and the globe, which arrive a few seconds later.
        instances.forEach { _ = ImageRenderer(content: WidgetView(instance: $0)).cgImage }
        let deadline = Date.now.addingTimeInterval(20)
        while Date.now < deadline, !mapsReady() {
            RunLoop.main.run(until: .now.addingTimeInterval(0.25))
        }
        // Live updates, such as the battery and system monitors, may have landed while waiting.
        loadSamples()

        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written = 0
        for instance in instances {
            let name = "\(instance.kind.rawValue)-\(instance.style)-\(instance.size.rawValue).png"
            if write(WidgetView(instance: instance), to: folder.appendingPathComponent(name), scale: 2) {
                written += 1
            } else {
                print("Couldn't draw \(name)")
            }
        }
        print("Drew \(written) of \(instances.count) widgets into \(folder.path)")
        let extras = drawExtras(into: folder)
        exit(written == instances.count && extras ? 0 : 1)
    }

    /// The icons the website shows beside the pictures: each settings page's and widget's tile, and the
    /// island's symbols in white, for the page to colour.
    @MainActor
    private static func drawExtras(into folder: URL) -> Bool {
        let icons = folder.appendingPathComponent("icons", isDirectory: true)
        let symbols = folder.appendingPathComponent("symbols", isDirectory: true)
        for url in [icons, symbols] {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        var ok = true
        for kind in WidgetKind.allCases {
            ok = write(WidgetIcon(kind: kind, size: 26), to: icons.appendingPathComponent("\(kind.rawValue).png"), scale: 4) && ok
        }
        let pages: [(String, String, Color)] = [
            ("general", "gearshape.fill", .gray), ("whatsNew", "sparkles", .pink), ("layoutStudio", "rectangle.3.group.fill", .blue),
            ("layoutGallery", "square.grid.2x2.fill", .indigo), ("appearance", "paintpalette.fill", .teal),
            ("stickyNotes", "note.text", .yellow), ("island", "capsule.fill", .black), ("about", "info.circle.fill", .indigo),
        ]
        for (name, symbol, color) in pages {
            ok = write(SidebarIcon(symbol: symbol, color: color), to: icons.appendingPathComponent("page-\(name).png"), scale: 4) && ok
        }
        for name in ["personalhotspot", "timer", "stopwatch"] {
            let glyph = Image(systemName: name)
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 80, height: 80)
            ok = write(glyph, to: symbols.appendingPathComponent("\(name).png"), scale: 2) && ok
        }
        return ok
    }

    private static func instances() -> [WidgetInstance] {
        WidgetKind.allCases.flatMap { kind in
            kind.styles.flatMap { style in
                style.sizes.map { size in
                    var instance = kind.sample(style: style.id, size: size)
                    switch kind {
                    case .stickyNote:
                        instance.config = ["text": "Water the plants 🌿\nCall the bike shop\nGym at 6", "color": NoteColor.yellow.rawValue]
                    case .favorites where style.id == "single":
                        instance.config = ["apps": "com.apple.Music"]
                    case .favorites where style.id == "pair":
                        instance.config = ["apps": "com.apple.MobileSMS,com.apple.Safari"]
                    case .countdown:
                        let date = Date.now.addingTimeInterval(23 * 86400 + 6 * 3600 + 14 * 60)
                        instance.config = ["title": "Trip to Lisbon", "date": String(date.timeIntervalSince1970)]
                    default: break
                    }
                    return instance
                }
            }
        }
    }

    private static func mapsReady() -> Bool {
        guard EarthStore.shared.image != nil, let report = WeatherStore.shared.report else { return false }
        return WidgetKind.location.styles.allSatisfy { style in
            style.sizes.allSatisfy {
                MapSnapshots.shared.image(latitude: report.latitude, longitude: report.longitude, size: $0, style: style.id) != nil
            }
        }
    }

    @MainActor
    private static func write(_ view: some View, to url: URL, scale: CGFloat) -> Bool {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = false
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { return false }
        return (try? data.write(to: url)) != nil
    }
}
#endif

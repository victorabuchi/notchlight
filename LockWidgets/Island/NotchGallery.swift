#if DEBUG
import AppKit
import SwiftUI

/// Test builds only: draws Light, the Tray, the drop area and the welcome with sample data to PNG files, to
/// check their design, then quits before any window or island appears. Run the test copy with
/// `-renderNotch <folder> -gallerySamples scripts/gallery-samples -notchWall <wallpaper>`.
enum NotchGallery {
    static let folder = UserDefaults.standard.string(forKey: "renderNotch").map { URL(fileURLWithPath: $0, isDirectory: true) }

    @MainActor
    static func run(into folder: URL) -> Never {
        let samples = UserDefaults.standard.string(forKey: "gallerySamples").map { URL(fileURLWithPath: $0, isDirectory: true) }
        NowPlayingStore.shared.loadSample(artwork: samples.flatMap { NSImage(contentsOf: $0.appendingPathComponent("cover.jpg")) })
        LyricsStore.shared.loadSample()
        let wall = UserDefaults.standard.string(forKey: "notchWall").flatMap { NSImage(contentsOfFile: $0) }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let notch = CGSize(width: 185, height: 32)

        func light(_ name: String, _ configure: (LightModel) -> Void) {
            let model = LightModel()
            model.notch = notch
            model.isOpen = true
            configure(model)
            write(LightView(model: model), to: folder.appendingPathComponent("\(name).png"), wall: wall)
        }
        func welcome(_ name: String, _ configure: (WelcomeModel) -> Void) {
            let model = WelcomeModel()
            model.notch = notch
            model.isOpen = true
            model.helloProgress = 1
            model.showsText = true
            model.licence = .trial(daysLeft: LicenseStore.trialDays)
            configure(model)
            write(WelcomeView(model: model), to: folder.appendingPathComponent("\(name).png"), wall: wall)
        }

        light("light") { $0.page = .light }
        TrayStore.shared.loadSample([])
        light("tray-empty") { $0.page = .tray }
        let files = ["README.md", "project.yml", "docs/assets/og.jpg", "docs/index.html"].map { URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent($0) }
        TrayStore.shared.loadSample(files)
        light("tray-files") { $0.page = .tray }
        light("drop") { $0.isDropping = true }
        welcome("welcome-hello") { $0.showsText = false }
        welcome("welcome-trial") { _ in }
        welcome("welcome-licensed") { $0.licence = .licensed }
        welcome("tutorial") { $0.page = .tutorial }
        print("Drew the notch into \(folder.path)")
        exit(0)
    }

    @MainActor
    private static func write(_ view: some View, to url: URL, wall: NSImage?) {
        let canvas = view
            .frame(width: 900, height: 330)
            .background {
                if let wall {
                    Image(nsImage: wall).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray
                }
            }
            .clipped()
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        guard let image = renderer.cgImage, let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
#endif

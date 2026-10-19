import AppKit
import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// Light: the notch opened wide. A click on the notch drops it down with the song that's playing and a mirror
/// from the camera, and a Tray that holds files dragged to the notch until you drag them out again. Dragging
/// files to the notch opens it with places to drop them: the Tray, or AirDrop.
final class LightController {
    static let shared = LightController()

    let model = LightModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var leftAt: Date?
    private var swipe = SwipeTracker()
    private var monitor: Any?
    /// Bumped on every open and close, so a close scheduled by an earlier one doesn't run.
    private var generation = 0

    var isOpen: Bool { panel?.isVisible == true && model.isOpen }

    /// Opens Light on a page; with no page, on the Tray while it holds files (if that's chosen), or on Light.
    func open(_ page: LightModel.Page? = nil, forDrop: Bool = false) {
        guard !WelcomeController.shared.isShowing else { return }
        if let page {
            model.page = page
        } else if !isOpen {
            let tray = SettingsKey.isOn(SettingsKey.trayOpensWithFiles) && !TrayStore.shared.files.isEmpty
            model.page = tray ? .tray : .light
        }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { model.isDropping = forDrop }
        guard !isOpen else { return }

        generation += 1
        let island = IslandModel.shared
        if panel == nil { makePanel() }
        model.notch = island.notch
        // It grows out of whatever the island is showing, and folds back into it.
        model.startSize = island.size == .zero ? island.notch : island.size
        model.isOpen = false
        panel?.hang(model.openSize)
        IslandController.shared.isSuppressed = true
        panel?.orderFrontRegardless()
        DispatchQueue.main.async { [model] in
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { model.isOpen = true }
        }
        leftAt = nil
        let timer = Timer(timeInterval: 1.0 / 20, repeats: true) { [weak self] _ in self?.track() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func close() {
        guard panel?.isVisible == true, model.isOpen else { return }
        generation += 1
        let current = generation
        timer?.invalidate()
        timer = nil
        MirrorCamera.shared.stop()
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) {
            model.isOpen = false
            model.isDropping = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, generation == current else { return }
            panel?.orderOut(nil)
            IslandController.shared.isSuppressed = false
        }
    }

    /// Closes Light shortly after the pointer leaves it, unless a drag is still on its way.
    private func track() {
        guard let panel else { return }
        let inside = panel.frame.insetBy(dx: -6, dy: -6).contains(NSEvent.mouseLocation)
        let dragging = NSEvent.pressedMouseButtons & 1 != 0
        if inside || dragging {
            leftAt = nil
        } else if let left = leftAt {
            if Date.now.timeIntervalSince(left) > 0.5 { close() }
        } else {
            leftAt = .now
        }
        // A drag that ends outside the drop zones takes them away again.
        if model.isDropping, !dragging, !inside { withAnimation { model.isDropping = false } }
    }

    private func makePanel() {
        let panel = NSPanel.atNotch(level: .statusBar + 8)
        panel.contentView = NotchHostingView(rootView: LightView(model: model))
        self.panel = panel
        // Swipe up to fold Light away; sideways to change songs.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if let direction = swipe.feed(event) { swiped(direction) }
            return nil
        }
    }

    private func swiped(_ direction: SwipeTracker.Direction) {
        guard SettingsKey.isOn(SettingsKey.gestures) else { return }
        switch direction {
        case .up where SettingsKey.isOn(SettingsKey.gestureOpenClose):
            close()
        case .left, .right:
            IslandController.changeSong(direction)
        default:
            break
        }
    }

    /// Settings, from Light's gear.
    func openSettings() {
        close()
        NotificationCenter.default.post(name: AppDelegate.openNotchSettings, object: nil)
    }
}

final class LightModel: ObservableObject {
    enum Page: CaseIterable {
        case light, tray

        var title: String { self == .light ? "Light" : "Tray" }
        var symbol: String { self == .light ? "lamp.desk.fill" : "tray.fill" }
    }

    @Published var page: Page = .light
    @Published var isOpen = false
    /// Files are being dragged to the notch: Light shows where they can go.
    @Published var isDropping = false
    var notch = CGSize(width: 185, height: 32)
    var startSize = CGSize(width: 185, height: 32)

    var openSize: CGSize { CGSize(width: max(notch.width + 280, 480), height: notch.height + 148) }
    var size: CGSize { isOpen ? openSize : startSize }
}

struct LightView: View {
    @ObservedObject var model: LightModel
    @AppStorage(SettingsKey.liquidGlass) private var liquid = false

    var body: some View {
        let size = model.size
        let radius: CGFloat = model.isOpen ? 26 : IslandModel.notchRadius
        ZStack(alignment: .top) {
            IslandSurface(bottomRadius: radius, glass: liquid && model.isOpen)
            VStack(spacing: 0) {
                header
                    .frame(height: model.notch.height)
                Group {
                    if model.isDropping {
                        DropZones(model: model)
                    } else if model.page == .light {
                        LightMedia()
                    } else {
                        TrayPage(model: model)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 16)
                .frame(maxHeight: .infinity)
            }
            .frame(width: model.openSize.width, height: model.openSize.height)
            .opacity(model.isOpen ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(IslandShape(bottomRadius: radius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    /// Either side of the camera: the two pages on the left, settings on the right.
    private var header: some View {
        HStack(spacing: 6) {
            ForEach(LightModel.Page.allCases, id: \.self) { page in
                let selected = model.page == page && !model.isDropping
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        model.isDropping = false
                        model.page = page
                    }
                } label: {
                    Image(systemName: page.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(selected ? 1 : 0.5))
                        .frame(width: 36, height: 24)
                        .background(Capsule().fill(Color.white.opacity(selected ? 0.16 : 0)))
                        .contentShape(Capsule())
                }
                .buttonStyle(IslandButtonStyle())
                .help(page.title)
            }
            Spacer()
            Button { LightController.shared.openSettings() } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 28, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IslandButtonStyle())
            .help("Notch Settings")
        }
        .padding(.horizontal, 14)
    }
}

// MARK: Light

/// The song that's playing, with its controls and progress, beside the mirror.
private struct LightMedia: View {
    @ObservedObject private var music = NowPlayingStore.shared
    @ObservedObject private var lyrics = LyricsStore.shared
    @AppStorage(SettingsKey.lightMirror) private var mirror = true
    @AppStorage(SettingsKey.islandLyrics) private var showLyrics = true

    var body: some View {
        HStack(spacing: 0) {
            Group {
                if let track = music.track {
                    player(track)
                } else {
                    nothingPlaying
                }
            }
            .frame(maxWidth: .infinity)
            if mirror {
                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 1)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                MirrorCircle(size: 108)
            }
        }
    }

    private func player(_ track: NowPlayingStore.Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Artwork(image: music.artwork, size: 72, cornerRadius: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 14, weight: .bold))
                    if !track.album.isEmpty, track.album != track.title {
                        Text(track.album)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Text(track.artist)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                    if showLyrics { lyricLine }
                    HStack(spacing: 16) {
                        control("backward.fill", 14) { music.send(.previous) }
                        control(music.isPlaying ? "pause.fill" : "play.fill", 19) { music.send(.playPause) }
                        control("forward.fill", 14) { music.send(.next) }
                    }
                    .padding(.top, 5)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            TimelineView(.periodic(from: .now, by: 0.5)) { context in
                let position = music.position(at: context.date)
                VStack(spacing: 4) {
                    Scrubber(fraction: track.duration > 0 ? position / track.duration : 0) { fraction in
                        music.seek(to: fraction * track.duration)
                    }
                    HStack {
                        Text(position.playbackTime)
                        Spacer()
                        Text("-" + (track.duration - position).playbackTime)
                    }
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
    }

    /// The line Apple Music is on, as in the island's card.
    private var lyricLine: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { context in
            if lyrics.state == .found, let index = lyrics.currentIndex(at: music.position(at: context.date)) {
                Text(lyrics.lines[index].text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(nsColor: music.artworkColor ?? .systemPink))
                    .id(index)
                    .transition(.push(from: .bottom))
                    .animation(.easeInOut(duration: 0.3), value: index)
            }
        }
        .frame(height: 16, alignment: .leading)
        .clipped()
    }

    /// With no song, the players to start one in.
    private var nothingPlaying: some View {
        VStack(spacing: 4) {
            Text("Nothing is playing")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.6))
            Text("Start some music?")
                .font(.system(size: 14, weight: .bold))
            HStack(spacing: 14) {
                ForEach(NowPlayingStore.Player.allCases, id: \.self) { player in
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: player.rawValue) {
                        Button {
                            NSWorkspace.shared.openApplication(at: url, configuration: .init())
                        } label: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable()
                                .frame(width: 40, height: 40)
                        }
                        .buttonStyle(IslandButtonStyle())
                        .help(player.name)
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func control(_ symbol: String, _ size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .bold))
                .frame(width: 26, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(IslandButtonStyle())
    }
}

/// The song's progress, which you can click or drag along to move through it.
private struct Scrubber: View {
    let fraction: Double
    let seek: (Double) -> Void
    @State private var dragging: Double?

    var body: some View {
        GeometryReader { proxy in
            let shown = min(max(dragging ?? fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Color.white).frame(width: proxy.size.width * shown)
            }
            .frame(height: dragging == nil ? 5 : 7)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { dragging = $0.location.x / max(proxy.size.width, 1) }
                    .onEnded { value in
                        seek(min(max(value.location.x / max(proxy.size.width, 1), 0), 1))
                        dragging = nil
                    }
            )
            .animation(.easeOut(duration: 0.15), value: dragging == nil)
        }
        .frame(height: 12)
    }
}

/// The camera in a circle, like a pocket mirror. It turns on when clicked, and off again with a click or when
/// Light closes.
private struct MirrorCircle: View {
    let size: CGFloat
    @ObservedObject private var camera = MirrorCamera.shared

    var body: some View {
        Button { camera.toggle() } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.1))
                if camera.isRunning {
                    CameraPreview(session: camera.session)
                        .clipShape(Circle())
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: camera.isDenied ? "video.slash" : "web.camera")
                            .font(.system(size: 26, weight: .regular))
                        Text(camera.isDenied ? "No Camera Access" : "Mirror")
                            .font(.system(size: 12, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.white.opacity(0.55))
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
        }
        .buttonStyle(IslandButtonStyle())
    }
}

/// The front camera for the mirror, running only while the mirror is on.
final class MirrorCamera: ObservableObject {
    static let shared = MirrorCamera()

    let session = AVCaptureSession()
    @Published private(set) var isRunning = false
    @Published private(set) var isDenied = false
    private let queue = DispatchQueue(label: "Notchlight.Mirror")
    private var configured = false

    func toggle() {
        isRunning ? stop() : start()
    }

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async { granted ? self.run() : (self.isDenied = true) }
            }
        default:
            isDenied = true
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func run() {
        isDenied = false
        isRunning = true
        queue.async { [self] in
            if !configured {
                session.beginConfiguration()
                session.sessionPreset = .medium
                if let device = AVCaptureDevice.default(for: .video),
                   let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input)
                {
                    session.addInput(input)
                }
                session.commitConfiguration()
                configured = true
            }
            session.startRunning()
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        queue.async { [session] in session.stopRunning() }
    }
}

/// The camera's picture, mirrored like a mirror and filling a round frame.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context _: Context) -> PreviewView {
        PreviewView(session: session)
    }

    func updateNSView(_: PreviewView, context _: Context) {}

    final class PreviewView: NSView {
        private let preview: AVCaptureVideoPreviewLayer

        init(session: AVCaptureSession) {
            preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            super.init(frame: .zero)
            wantsLayer = true
            layer = preview
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) { nil }

        override func layout() {
            super.layout()
            preview.cornerRadius = min(bounds.width, bounds.height) / 2
            preview.masksToBounds = true
            // The connection appears once the camera is set up.
            if let connection = preview.connection, connection.isVideoMirroringSupported, !connection.isVideoMirrored {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
    }
}

// MARK: Tray

/// Files dragged to the notch, kept until they're dragged out again. The Tray holds links to the files, not
/// copies, so they stay where they are; files moved or deleted since drop out of it.
final class TrayStore: ObservableObject {
    static let shared = TrayStore()

    @Published private(set) var files: [URL] = []

    private init() {
        let paths = UserDefaults.standard.stringArray(forKey: SettingsKey.trayFiles) ?? []
        files = paths.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ urls: [URL]) {
        for url in urls where !files.contains(url) {
            files.append(url)
        }
        save()
    }

    func remove(_ url: URL) {
        files.removeAll { $0 == url }
        save()
    }

    func clear() {
        files = []
        save()
    }

    private func save() {
        #if DEBUG
        if WidgetGallery.isRendering { return }
        #endif
        UserDefaults.standard.set(files.map(\.path), forKey: SettingsKey.trayFiles)
    }

    #if DEBUG
    /// Files to show in pictures of the Tray, without saving them.
    func loadSample(_ urls: [URL]) {
        files = urls
    }
    #endif
}

private struct TrayPage: View {
    @ObservedObject var model: LightModel
    @ObservedObject private var tray = TrayStore.shared
    @State private var targeted = false

    var body: some View {
        ZStack {
            if tray.files.isEmpty {
                DashedZone(highlighted: targeted) {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.fill")
                            .font(.system(size: 24))
                        Text("Files Tray")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Drag files to the notch to keep them here.")
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Sideways {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(tray.files, id: \.self) { url in
                            TrayFile(url: url)
                        }
                    }
                    .padding(.horizontal, 4)
                    .frame(maxHeight: .infinity)
                }
                .overlay(alignment: .bottomTrailing) {
                    Button("Clear") { withAnimation { tray.clear() } }
                        .buttonStyle(IslandButtonStyle())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(targeted ? 0.08 : 0))
                }
            }
        }
        .fileDrop(isTargeted: $targeted) { TrayStore.shared.add($0) }
    }
}

/// A file in the Tray: its icon and name. Drag it out to move it on, click to open it, × to let it go.
private struct TrayFile: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 46, height: 46)
            Text(url.lastPathComponent)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .padding(6)
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button { withAnimation { TrayStore.shared.remove(url) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color(white: 0.3))
                }
                .buttonStyle(IslandButtonStyle())
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .onDrag { NSItemProvider(object: url as NSURL) }
        .help(url.path)
    }
}

// MARK: Drop area

/// Where files dragged to the notch can go: the Tray, or AirDrop.
private struct DropZones: View {
    @ObservedObject var model: LightModel
    @AppStorage(SettingsKey.dropAirDrop) private var airDrop = true
    @State private var overTray = false
    @State private var overAirDrop = false

    var body: some View {
        HStack(spacing: 12) {
            zone("Tray", "tray.and.arrow.down.fill", "Keep them here", targeted: $overTray) { urls in
                TrayStore.shared.add(urls)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    model.isDropping = false
                    model.page = .tray
                }
            }
            if airDrop {
                zone("AirDrop", "dot.radiowaves.left.and.right", "Send to a nearby device", targeted: $overAirDrop) { urls in
                    LightController.shared.close()
                    NSApp.activate()
                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: urls)
                }
            }
        }
    }

    private func zone(_ title: String, _ symbol: String, _ detail: String, targeted: Binding<Bool>, drop: @escaping ([URL]) -> Void) -> some View {
        DashedZone(highlighted: targeted.wrappedValue) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 24))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white.opacity(targeted.wrappedValue ? 1 : 0.6))
        }
        .fileDrop(isTargeted: targeted, then: drop)
    }

    /// The file URLs from a drop, delivered on the main queue.
    fileprivate static func load(_ providers: [NSItemProvider], then done: @escaping ([URL]) -> Void) {
        let group = DispatchGroup()
        var urls: [URL] = []
        let lock = NSLock()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            if !urls.isEmpty { done(urls) }
        }
    }
}

extension View {
    /// Takes files dropped on the view. Test pictures leave it out, as they can't draw drop targets.
    @ViewBuilder
    fileprivate func fileDrop(isTargeted: Binding<Bool>, then done: @escaping ([URL]) -> Void) -> some View {
        #if DEBUG
        if WidgetGallery.isRendering {
            self
        } else {
            onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
                DropZones.load(providers, then: done)
                return true
            }
        }
        #else
        onDrop(of: [.fileURL], isTargeted: isTargeted) { providers in
                DropZones.load(providers, then: done)
                return true
            }
        #endif
    }
}

/// A row that scrolls sideways when it's longer than Light is wide. Test pictures show it unscrolled.
private struct Sideways<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if DEBUG
        if WidgetGallery.isRendering {
            content.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            ScrollView(.horizontal, showsIndicators: false) { content }
        }
        #else
        ScrollView(.horizontal, showsIndicators: false) { content }
        #endif
    }
}

/// A rounded box with a dashed edge, which turns solid when something can be dropped in it.
private struct DashedZone<Content: View>: View {
    let highlighted: Bool
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(shape.fill(Color.white.opacity(highlighted ? 0.1 : 0)))
            .overlay(shape.strokeBorder(Color.white.opacity(highlighted ? 0.7 : 0.28), style: StrokeStyle(lineWidth: 2, dash: highlighted ? [] : [7, 6])))
            .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}

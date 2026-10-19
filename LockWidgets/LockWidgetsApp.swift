import ServiceManagement
import SwiftUI

@main
struct LockWidgetsApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var overlay: OverlayManager

    init() {
        #if DEBUG
        if let folder = WidgetGallery.folder { WidgetGallery.run(into: folder) }
        if let folder = NotchGallery.folder { NotchGallery.run(into: folder) }
        #endif
        // Before anything reads a setting.
        PreferencesMigration.run()
        _overlay = StateObject(wrappedValue: OverlayManager())
        IslandController.shared.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(overlay: overlay)
        } label: {
            MenuBarLabel()
        }

        Window("Notchlight", id: "settings") {
            SettingsWindow(overlay: overlay)
        }
        .defaultSize(width: 1100, height: 740)
        .defaultLaunchBehavior(.suppressed)

        Window("Welcome to Notchlight", id: "setup") {
            SetupGuide()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Trip", id: "trip") {
            TripStartView()
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        // Notch Settings: the island, Light, the Tray and gestures, with tabs along the top.
        Settings {
            NotchSettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static let openSettings = Notification.Name("LockWidgets.openSettings")
    /// Opens settings on the page carried as the notification's object.
    static let openPage = Notification.Name("LockWidgets.openPage")
    /// Opens Notch Settings, on the tab carried as the notification's object if there is one.
    static let openNotchSettings = Notification.Name("LockWidgets.openNotchSettings")

    /// True when macOS started the app at login, where opening a window would be unwelcome.
    private(set) static var launchedAtLogin = false

    func applicationWillFinishLaunching(_: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginItem = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
        // Login items registered with SMAppService don't always carry that flag, so also treat a launch right after boot as one.
        Self.launchedAtLogin = loginItem || ProcessInfo.processInfo.systemUptime < 120
    }

    /// Keeps App Nap from slowing LockWidgets down in the background, so the island reacts instantly.
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_: Notification) {
        Updater.shared.start()
        ActivityTracker.shared.start()
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Live widgets and the Dynamic Island"
        )
    }

    /// Opening the app again from Finder, Launchpad or the Dock shows its window.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            NotificationCenter.default.post(name: Self.openSettings, object: nil)
        }
        return true
    }
}

/// The status item icon. It renders at launch, so it also opens the first window.
private struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @AppStorage(SettingsKey.hasLaunched) private var hasLaunched = false
    @State private var frame = 0
    @State private var player: Timer?

    var body: some View {
        Image(nsImage: MenuBarIcon.frames[frame])
            .accessibilityLabel("Notchlight")
            // Bounces for anything new on the island: a notification, a call, an event, a device or the charger.
            .onReceive(IslandModel.shared.$primary.map { $0?.bounceKey }.removeDuplicates()) { key in
                if key != nil { bounce() }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { bounce() }
                #if DEBUG
                if SettingsPage.launchPage != nil {
                    openWindow(id: "settings")
                    return
                }
                #endif
                // When the free trial has ended, settings open on the Licence page.
                if LicenseStore.shared.state == .expired { SettingsRouter.shared.page = .licence }
                if !hasLaunched {
                    // The first time, "hello" from the notch; its trial button leads on to the Setup Guide.
                    WelcomeController.shared.show()
                } else if !AppDelegate.launchedAtLogin || LicenseStore.shared.state == .expired {
                    openWindow(id: "settings")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { DockPolicy.bringWindowsForward() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openSettings)) { _ in
                openWindow(id: hasLaunched ? "settings" : "setup")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { DockPolicy.bringWindowsForward() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openNotchSettings)) { note in
                if let tab = note.object as? NotchTab { NotchSettingsRouter.shared.tab = tab }
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { DockPolicy.update() }
            }
            .onReceive(NotificationCenter.default.publisher(for: AppDelegate.openPage)) { note in
                if let page = note.object as? SettingsPage { SettingsRouter.shared.page = page }
                openWindow(id: "settings")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { DockPolicy.bringWindowsForward() }
            }
    }

    /// Plays the bounce once, unless Reduce Motion is on.
    private func bounce() {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        player?.invalidate()
        frame = 0
        player = Timer.scheduledTimer(withTimeInterval: 1 / MenuBarIcon.framesPerSecond, repeats: true) { timer in
            if frame + 1 < MenuBarIcon.frames.count {
                frame += 1
            } else {
                frame = 0
                timer.invalidate()
            }
        }
    }
}

/// The menu bar icon: SF Symbols' light.panel, with its Bounce effect. A menu bar extra shows its label as a
/// still image, so `.symbolEffect(.bounce)` can't run there; the bounce is played as frames of the symbol scaled
/// the way the effect moves it: a quick squeeze, an overshoot, then rest. Every frame is a template image, so the
/// icon tints with the menu bar like the system's own.
enum MenuBarIcon {
    static let framesPerSecond = 60.0

    /// The bounce from rest back to rest; the first frame is the icon at rest.
    static let frames: [NSImage] = {
        let keyframes: [(time: Double, scale: Double)] = [(0, 1), (0.1, 0.84), (0.26, 1.1), (0.4, 0.97), (0.52, 1.01), (0.62, 1)]
        let count = Int(keyframes.last!.time * framesPerSecond)
        return (0 ... count).map { index in
            let time = Double(index) / framesPerSecond
            let next = keyframes.firstIndex { $0.time >= time } ?? keyframes.count - 1
            guard next > 0 else { return image(scale: 1) }
            let (from, to) = (keyframes[next - 1], keyframes[next])
            let progress = (time - from.time) / (to.time - from.time)
            let eased = progress * progress * (3 - 2 * progress)
            return image(scale: from.scale + (to.scale - from.scale) * eased)
        }
    }()

    private static let symbol = NSImage(systemSymbolName: "light.panel", accessibilityDescription: "Notchlight")?
        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 15, weight: .regular))

    /// The symbol at a scale, centred on a canvas with room for the overshoot, so the item never changes width.
    private static func image(scale: Double) -> NSImage {
        let natural = symbol?.size ?? NSSize(width: 18, height: 14)
        let canvas = NSSize(width: ceil(natural.width * 1.12), height: ceil(max(natural.height * 1.12, 18)))
        let image = NSImage(size: canvas, flipped: false) { rect in
            let size = NSSize(width: natural.width * scale, height: natural.height * scale)
            symbol?.draw(in: NSRect(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2, width: size.width, height: size.height))
            return true
        }
        image.isTemplate = true
        return image
    }
}

private struct MenuContent: View {
    @ObservedObject var overlay: OverlayManager
    @ObservedObject private var timers = TimerStore.shared
    @ObservedObject private var updater = Updater.shared
    @ObservedObject private var trips = TripStore.shared
    @ObservedObject private var licence = LicenseStore.shared
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.showOnLockScreen) private var showOnLockScreen = true
    @AppStorage(SettingsKey.islandEnabled) private var islandEnabled = true

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    }

    private func openTripWindow() {
        openWindow(id: "trip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { DockPolicy.bringWindowsForward() }
    }

    var body: some View {
        Text("Notchlight \(version)")
        if let available = updater.availableVersion {
            Button("Update to Notchlight \(available)…") { updater.checkForUpdates() }
        }
        switch licence.state {
        case let .trial(daysLeft):
            Button("Free Trial, \(daysLeft == 1 ? "1 Day" : "\(daysLeft) Days") Left · Buy Notchlight…") {
                NSWorkspace.shared.open(LicenseStore.checkoutURL)
            }
        case .expired:
            Button("Trial Ended · Buy Notchlight…") { NSWorkspace.shared.open(LicenseStore.checkoutURL) }
            Button("Enter Licence Key…") { open(.licence) }
        case .licensed:
            EmptyView()
        }

        Divider()

        Button("Open Settings…") { open(.general) }
            .keyboardShortcut(",")
        Button("Notch Settings…") {
            NotificationCenter.default.post(name: AppDelegate.openNotchSettings, object: nil)
        }
        Button("Open Layout Studio…") { open(.layoutStudio) }
        Button("Browse Layout Gallery…") { open(.gallery) }
        Button(showOnLockScreen ? "Hide Widgets on Lock Screen" : "Show Widgets on Lock Screen") {
            showOnLockScreen.toggle()
        }
        Button(islandEnabled ? "Hide Dynamic Island" : "Show Dynamic Island") {
            islandEnabled.toggle()
        }
        Button(overlay.isShowing ? "Hide Desktop Preview" : "Preview on Desktop") {
            overlay.toggle()
        }
        .keyboardShortcut("p")

        Divider()

        Menu("Pomodoro · \(timers.phase.title) \(timers.pomodoroRemaining().clockText)") {
            Button(timers.pomodoroRunning ? "Pause" : "Start") { timers.togglePomodoro() }
            Button("Skip to Next Session") { timers.skipPhase() }
            Button("Reset") { timers.resetPomodoro() }
        }
        Menu("Stopwatch · \(timers.stopwatchElapsed().clockText)") {
            Button(timers.stopwatchRunning ? "Stop" : "Start") { timers.toggleStopwatch() }
            Button("Reset") { timers.resetStopwatch() }
        }
        if let trip = trips.trip {
            Menu("\(trip.title) · arrives \(trip.arrival.formatted(date: .omitted, time: .shortened))") {
                Button("Change Trip…") { openTripWindow() }
                Button("End Trip") { trips.end() }
            }
        } else {
            Button("Start a Trip…") { openTripWindow() }
        }
        Button("Refresh Widgets") { overlay.refreshData() }
            .keyboardShortcut("r")

        Divider()

        Button("What's New…") { open(.whatsNew) }
        Button("Check for Updates…") { updater.checkForUpdates() }
        Menu("Help & Support") {
            Button("Welcome to Notchlight…") { WelcomeController.shared.show() }
            Button("Setup Guide…") {
                openWindow(id: "setup")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { DockPolicy.bringWindowsForward() }
            }
            Button("Notchlight on GitHub") {
                NSWorkspace.shared.open(URL(string: "https://github.com/victorabuchi/notchlight")!)
            }
            Button("Report a Problem…") {
                NSWorkspace.shared.open(URL(string: "https://github.com/victorabuchi/notchlight/issues/new")!)
            }
        }
        Toggle("Launch at Login", isOn: Binding(
            get: { SMAppService.mainApp.status == .enabled },
            set: { enabled in
                try? enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
            }
        ))

        Divider()

        Button("Quit Notchlight") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func open(_ page: SettingsPage) {
        SettingsRouter.shared.page = page
        openWindow(id: "settings")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { DockPolicy.bringWindowsForward() }
    }
}

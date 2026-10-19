import AppKit
import Combine
import SwiftUI

/// A borderless panel over the notch that hosts the island and only takes clicks inside the island itself.
final class IslandController {
    static let shared = IslandController()

    private var panel: NSPanel?
    private var monitors: [Any] = []
    private var pointerTimer: Timer?
    private var lastPointer = NSPoint(x: -1, y: -1)
    private var subscriptions: Set<AnyCancellable> = []
    private var collapseWork: DispatchWorkItem?
    private var expandWork: DispatchWorkItem?
    private var holdWork: DispatchWorkItem?
    private var pressTarget: PressTarget?
    private var lightWork: DispatchWorkItem?
    private var swipe = SwipeTracker()
    /// The drag pasteboard's count when a file drag last opened Light, so one drag opens it once.
    private var lastDrag = NSPasteboard(name: .drag).changeCount
    private let canvas = CGSize(width: 760, height: 320)

    private enum PressTarget { case island, bubble, light }

    /// Set while the welcome or Light stands in for the island at the notch, so only one shape shows there.
    var isSuppressed = false {
        didSet { if isSuppressed != oldValue { update() } }
    }

    /// On when the setting is, and while the trial lasts or Notchlight is licensed.
    private var enabled: Bool {
        SettingsKey.isOn(SettingsKey.islandEnabled) && LicenseStore.shared.isActive && !isSuppressed
    }

    /// A click on the notch with nothing live in it opens Light.
    private var lightEnabled: Bool { SettingsKey.isOn(SettingsKey.lightEnabled) && LicenseStore.shared.isActive }

    func start() {
        let distributed = DistributedNotificationCenter.default()
        // While locked, the lock screen layer draws its own copy of the island (see OverlayManager);
        // this interactive one steps aside and comes back on unlock.
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            IslandModel.shared.isExpanded = false
            self?.panel?.orderOut(nil)
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.update()
        }
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
        LicenseStore.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.update() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.position() }
            .store(in: &subscriptions)

        // Follow the pointer by sampling its position rather than subscribing to every mouse movement:
        // global and local mouse-moved monitors stop clicks reaching LockWidgets' own windows on this macOS.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.trackMouse()
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer

        // Read presses at the AppKit level, so the first click always counts even though LockWidgets is
        // in the background. As on the iPhone, a click on the closed island opens the app behind it and
        // holding it opens the card (as resting the pointer on it does). Clicks inside the open card go
        // to its buttons.
        if let presses = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp], handler: { [weak self] event in
            guard let self, event.window === panel else { return event }
            let handled = event.type == .leftMouseDown ? pressBegan() : pressEnded()
            return handled ? nil : event
        }) {
            monitors.append(presses)
        }
        // Two-finger swipes on the island: down opens it, up closes it, sideways changes the song.
        if let swipes = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] event in
            guard let self, event.window === panel else { return event }
            if let direction = swipe.feed(event) { swiped(direction) }
            return nil
        }) {
            monitors.append(swipes)
        }
        update()
    }

    /// Returns true when the press belongs to the island or its circle rather than to the open card.
    private func pressBegan() -> Bool {
        let model = IslandModel.shared
        let point = NSEvent.mouseLocation
        if model.showsBubble, bubbleRect.insetBy(dx: -3, dy: -3).contains(point) {
            pressTarget = .bubble
            return true
        }
        if notchIsEmpty, notchRect.insetBy(dx: -4, dy: -4).contains(point) {
            pressTarget = .light
            return true
        }
        guard model.primary != nil else { return false }
        guard !model.isExpanded, rect(model.size).insetBy(dx: -4, dy: -4).contains(point) else { return false }
        pressTarget = .island
        expandWork?.cancel()
        expandWork = nil
        holdWork?.cancel()
        if model.primary?.canExpand == true {
            let work = DispatchWorkItem { [weak self] in
                self?.pressTarget = nil
                model.isExpanded = true
            }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
        }
        return true
    }

    /// A quick click opens the app behind what was clicked, unless the pointer slid off it first.
    private func pressEnded() -> Bool {
        holdWork?.cancel()
        holdWork = nil
        guard let target = pressTarget else { return false }
        pressTarget = nil
        if target == .light {
            if notchRect.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) { LightController.shared.open() }
            return true
        }
        let model = IslandModel.shared
        let area = target == .bubble ? bubbleRect : rect(model.size)
        guard area.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation),
              let activity = target == .bubble ? model.bubbleActivity : model.primary
        else { return true }
        IslandActions.open(activity)
        if activity.isTransient { model.dismissTransient() }
        return true
    }

    private func update() {
        if enabled {
            if panel == nil { makePanel() }
            position()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func makePanel() {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: canvas),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar + 8
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.contentView = FirstClickHostingView(rootView: IslandView())
        self.panel = panel
    }

    private func position() {
        guard let panel, let screen = IslandModel.screen else { return }
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.midX - canvas.width / 2, y: frame.maxY - canvas.height, width: canvas.width, height: canvas.height), display: true)
    }

    /// A rectangle of the given size hanging from the top of the screen, centred on the notch.
    private func rect(_ size: CGSize) -> NSRect {
        guard let screen = IslandModel.screen else { return .zero }
        return NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
    }

    /// The notch itself, where a click opens Light while nothing live is in it.
    private var notchRect: NSRect { rect(IslandModel.shared.notch) }

    /// Light is on and the notch has nothing live in it (quiet status may wait in the circle beside it).
    private var notchIsEmpty: Bool {
        let model = IslandModel.shared
        return lightEnabled && model.hasNotch && !model.isExpanded && (model.primary == nil || model.minorAlone)
    }

    private func swiped(_ direction: SwipeTracker.Direction) {
        guard SettingsKey.isOn(SettingsKey.gestures) else { return }
        let model = IslandModel.shared
        switch direction {
        case .down where SettingsKey.isOn(SettingsKey.gestureOpenClose):
            if lightEnabled {
                LightController.shared.open()
            } else if model.primary?.canExpand == true {
                model.isExpanded = true
            }
        case .up where SettingsKey.isOn(SettingsKey.gestureOpenClose):
            model.isExpanded = false
        case .left, .right:
            Self.changeSong(direction)
        default:
            break
        }
    }

    /// A sideways swipe plays the previous song (left) or the next (right), or the other way round when inverted.
    static func changeSong(_ direction: SwipeTracker.Direction) {
        let music = NowPlayingStore.shared
        guard SettingsKey.isOn(SettingsKey.gestureMedia), music.track != nil else { return }
        let next = (direction == .right) != SettingsKey.isOn(SettingsKey.gestureInvert, default: false)
        music.send(next ? .next : .previous)
    }

    /// The circle beside the island for a second live activity.
    private var bubbleRect: NSRect {
        let model = IslandModel.shared
        let island = rect(model.size)
        return NSRect(x: island.maxX + IslandModel.bubbleGap, y: island.maxY - model.bubbleSize, width: model.bubbleSize, height: model.bubbleSize)
    }

    /// Where the pointer counts as on the island: the island, its closed size while the card is open, and
    /// the circle beside it for a second live activity.
    private var hoverRect: NSRect {
        let model = IslandModel.shared
        var area = rect(model.size).union(rect(model.closedSize))
        if model.showsBubble {
            area.size.width += IslandModel.bubbleGap + model.bubbleSize
        }
        return area
    }

    private func trackMouse() {
        guard let panel, panel.isVisible else { return }
        let model = IslandModel.shared
        let pointer = NSEvent.mouseLocation
        let overIsland = hoverRect.insetBy(dx: -4, dy: -4).contains(pointer) && model.primary != nil
        let overEmptyNotch = notchIsEmpty && notchRect.insetBy(dx: -4, dy: -4).contains(pointer)
        let inside = overIsland || overEmptyNotch
        dragArrived(at: pointer)
        // Nothing to do while the pointer rests elsewhere.
        if pointer == lastPointer, panel.ignoresMouseEvents == !inside { return }
        lastPointer = pointer
        if panel.ignoresMouseEvents != !inside { panel.ignoresMouseEvents = !inside }
        if model.isHovering != overIsland { model.isHovering = overIsland }

        // Resting the pointer on the empty notch opens Light, when that's chosen.
        if overEmptyNotch, SettingsKey.isOn(SettingsKey.lightOnHover, default: false), pressTarget == nil {
            if lightWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    self?.lightWork = nil
                    LightController.shared.open()
                }
                lightWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
            }
        } else {
            lightWork?.cancel()
            lightWork = nil
        }

        // Resting the pointer on a live activity opens its card.
        if overIsland, !model.isExpanded, pressTarget == nil, model.primary?.canExpand == true, SettingsKey.isOn(SettingsKey.islandHoverOpens) {
            if expandWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    model.isExpanded = true
                    self?.expandWork = nil
                }
                expandWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
            }
        } else {
            expandWork?.cancel()
            expandWork = nil
        }

        // Close the full card shortly after the pointer leaves, however much it moves meanwhile.
        if model.isExpanded, !overIsland {
            if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in
                    model.isExpanded = false
                    self?.collapseWork = nil
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
            }
        } else {
            collapseWork?.cancel()
            collapseWork = nil
        }
    }
}

extension IslandController {
    /// Files dragged to the notch open Light with places to drop them. A drag is noticed from the drag
    /// pasteboard, which changes as each drag starts, so nothing has to watch every mouse movement.
    fileprivate func dragArrived(at pointer: NSPoint) {
        guard SettingsKey.isOn(SettingsKey.dropArea), lightEnabled, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        let board = NSPasteboard(name: .drag)
        guard board.changeCount != lastDrag else { return }
        let area = rect(IslandModel.shared.notch).insetBy(dx: -40, dy: -24)
        guard area.contains(pointer),
              board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
        else { return }
        lastDrag = board.changeCount
        LightController.shared.open(.tray, forDrop: true)
    }
}

/// Turns a two-finger swipe on a trackpad into one direction, once per swipe, in the direction the fingers moved
/// whatever the scrolling setting.
struct SwipeTracker {
    enum Direction { case left, right, up, down }

    private var x: CGFloat = 0
    private var y: CGFloat = 0
    private var fired = false

    mutating func feed(_ event: NSEvent) -> Direction? {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return nil }
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            x = 0
            y = 0
            fired = false
        }
        // With natural scrolling the deltas already follow the fingers; otherwise they run the other way.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        x += event.scrollingDeltaX * sign
        y += event.scrollingDeltaY * sign
        let ended = event.phase.contains(.ended) || event.phase.contains(.cancelled)
        defer {
            if ended {
                x = 0
                y = 0
                fired = false
            }
        }
        guard !fired else { return nil }
        if abs(x) > 50, abs(x) > abs(y) * 1.6 {
            fired = true
            return x > 0 ? .right : .left
        }
        if abs(y) > 28, abs(y) > abs(x) * 1.6 {
            fired = true
            return y > 0 ? .down : .up
        }
        return nil
    }
}

/// Lets the first click on the island act immediately, without activating LockWidgets first.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

/// What clicking the island opens, as tapping the iPhone's island does: the app behind the song, call or
/// notification, or the settings for the hotspot, a Bluetooth device, Focus, battery, sound or display.
enum IslandActions {
    static func open(_ activity: IslandActivity) {
        switch activity {
        case .music:
            openApp((NowPlayingStore.shared.track?.player ?? .music).rawValue)
        case .meeting:
            if let bundleID = StatusMonitor.shared.meeting?.bundleID { openApp(bundleID) }
        case .timer:
            // The Pomodoro and Stopwatch are LockWidgets' own.
            NotificationCenter.default.post(name: AppDelegate.openSettings, object: nil)
        case .hotspot:
            openSettings("com.apple.wifi-settings-extension")
        case .trip:
            openMaps(to: TripStore.shared.trip?.destination ?? "")
        case .reminders:
            openApp("com.apple.reminders")
        case .homeTime, .timeZone:
            openApp("com.apple.clock")
        case let .notification(item):
            openApp(item.bundleID)
        case .event:
            openApp("com.apple.iCal")
        case .device:
            openSettings("com.apple.BluetoothSettings")
        case .focus:
            openSettings("com.apple.Focus-Settings.extension")
        case .charging, .lowBattery:
            openSettings("com.apple.Battery-Settings.extension")
        case .volume:
            openSettings("com.apple.Sound-Settings.extension")
        case .lock:
            break
        case .brightness:
            openSettings("com.apple.Displays-Settings.extension")
        }
    }

    private static func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    /// Maps with directions to the trip's destination, or just Maps when there's no destination.
    private static func openMaps(to destination: String) {
        var components = URLComponents(string: "maps://")!
        if !destination.isEmpty { components.queryItems = [URLQueryItem(name: "daddr", value: destination)] }
        if let url = components.url { NSWorkspace.shared.open(url) }
    }

    private static func openSettings(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

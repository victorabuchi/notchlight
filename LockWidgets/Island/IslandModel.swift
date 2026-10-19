import AppKit
import Combine
import SwiftUI

/// Something the island can show, from a playing song to a passing alert.
enum IslandActivity: Equatable {
    // Ongoing, while the thing lasts.
    case meeting
    case timer
    case music
    case hotspot
    /// A bus, train or plane journey: the time it leaves, then the time left.
    case trip
    /// Reminders due today.
    case reminders
    /// The time back home, while the Mac is in another time zone.
    case homeTime
    /// The Mac is locked; anything live waits in the circle beside it. `open` for a moment as you unlock, as
    /// on the iPhone.
    case lock(open: Bool)
    // Brief, shown for a few seconds over everything else.
    case charging(level: Int, pluggedIn: Bool)
    case lowBattery(level: Int)
    case notification(NotificationStore.Item)
    case event(title: String, start: Date, color: NSColor)
    case device(name: String, symbol: String, connected: Bool)
    case volume(level: Double, muted: Bool)
    case brightness(level: Double)
    case focus(name: String, symbol: String, on: Bool)
    case timeZone(city: String, detail: String)

    var isTransient: Bool {
        switch self {
        case .meeting, .timer, .music, .hotspot, .trip, .reminders, .homeTime: false
        case let .lock(open): open
        default: true
        }
    }

    var isLock: Bool {
        if case .lock = self { return true }
        return false
    }

    /// Quiet status that waits in the circle beside the notch when nothing else is live.
    var isMinor: Bool {
        switch self {
        case .hotspot, .reminders, .homeTime: true
        default: false
        }
    }

    /// Banners open out like the full card instead of dropping a row below the notch.
    var isBanner: Bool {
        switch self {
        case .notification, .event: true
        default: false
        }
    }

    /// Height of the open card, or a banner, below the notch.
    var expandedHeight: CGFloat {
        switch self {
        case .music: MusicExpanded.height(showsLyrics: UserDefaults.standard.object(forKey: SettingsKey.islandLyrics) as? Bool ?? true)
        case .notification: 60
        case .hotspot: 44
        case .trip: 64
        case .reminders: 66
        default: 46
        }
    }

    var canExpand: Bool { !isTransient && !isLock }

    /// What the menu bar icon bounces for: something new arriving. A song, timer or hotspot just sits there, and
    /// volume and brightness change too often to bounce for.
    var bounceKey: String? {
        switch self {
        case let .notification(item): "notification \(item.id)"
        case let .event(title, start, _): "event \(title) \(start.timeIntervalSince1970)"
        case let .device(name, _, connected): "device \(name) \(connected)"
        case let .focus(name, _, on): "focus \(name) \(on)"
        case let .charging(_, pluggedIn): "charging \(pluggedIn)"
        case .lowBattery: "low battery"
        case .meeting: "meeting"
        case let .timeZone(city, _): "time zone \(city)"
        case .music, .timer, .hotspot, .trip, .reminders, .homeTime, .lock, .volume, .brightness: nil
        }
    }
}

/// What the island is showing and how big it is. Shared by the window (for hit testing) and the view.
final class IslandModel: ObservableObject {
    static let shared = IslandModel()

    @Published private(set) var primary: IslandActivity?
    /// A second live activity, shown as a small icon on the right of the open card, as the iPhone does.
    @Published private(set) var secondary: IslandActivity?
    @Published var isExpanded = false
    @Published var isHovering = false

    /// The notch, or a stand-in on displays without one.
    @Published private(set) var notch = CGSize(width: 190, height: 32)
    @Published private(set) var hasNotch = false

    private var transient: IslandActivity?
    private var transientWork: DispatchWorkItem?
    /// Brief activities waiting their turn, so a burst of notifications plays one after another.
    private var pending: [(IslandActivity, Double)] = []
    /// When the charger last went in or out.
    private var powerChangedAt = Date.distantPast
    private var isLocked = false
    private var pendingBrightness: DispatchWorkItem?
    /// Banner widths by app, measured once per app.
    private var bannerWidths: [String: CGFloat] = [:]
    private var subscriptions: Set<AnyCancellable> = []

    private init() {
        updateNotch()
        let music = NowPlayingStore.shared
        let timers = TimerStore.shared
        let status = StatusMonitor.shared
        let battery = BatteryMonitor.shared

        Publishers.MergeMany(
            music.$track.map { _ in () }.eraseToAnyPublisher(),
            timers.$pomodoroRunning.map { _ in () }.eraseToAnyPublisher(),
            timers.$stopwatchRunning.map { _ in () }.eraseToAnyPublisher(),
            status.$isOnHotspot.map { _ in () }.eraseToAnyPublisher(),
            status.$meeting.map { $0?.app }.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            TripStore.shared.$trip.map { _ in () }.eraseToAnyPublisher(),
            RemindersStore.shared.$items.map { _ in () }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification).map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.updateNotch() }
            .store(in: &subscriptions)

        battery.$isPluggedIn.removeDuplicates().dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] plugged in
                self?.powerChangedAt = .now
                self?.pendingBrightness?.cancel()
                guard self?.setting(SettingsKey.islandBattery) == true else { return }
                self?.show(.charging(level: battery.level ?? 0, pluggedIn: plugged), for: 4)
            }
            .store(in: &subscriptions)
        battery.$level.compactMap { $0 }.removeDuplicates()
            .scan((previous: 100, current: 100)) { ($0.current, $1) }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] change in
                guard self?.setting(SettingsKey.islandBattery) == true, !battery.isPluggedIn else { return }
                for threshold in [20, 10] where change.previous > threshold && change.current <= threshold {
                    self?.show(.lowBattery(level: change.current), for: 6)
                }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.updateNotch() }
            .store(in: &subscriptions)

        NotificationStore.shared.onNotification = { [weak self] item in
            guard self?.setting(SettingsKey.islandNotifications) == true else { return }
            self?.show(.notification(item), for: 5)
        }

        DeviceMonitor.shared.onEvent = { [weak self] event in
            guard let self else { return }
            switch event {
            case let .device(name, symbol, connected):
                if setting(SettingsKey.islandDevices) { show(.device(name: name, symbol: symbol, connected: connected), for: 3.5) }
            case let .volume(level, muted):
                if setting(SettingsKey.islandHUD) { show(.volume(level: level, muted: muted), for: 1.6) }
            case let .brightness(level):
                // macOS changes the brightness itself when the charger goes in or out; the charging alert says
                // what happened, so that change is dropped. It can arrive a moment before the charger is
                // reported, so it waits briefly to see.
                guard setting(SettingsKey.islandHUD) else { break }
                pendingBrightness?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self, Date.now.timeIntervalSince(powerChangedAt) > 5 else { return }
                    show(.brightness(level: level), for: 1.6)
                }
                pendingBrightness = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            case let .focus(name, symbol, on):
                if setting(SettingsKey.islandFocus) { show(.focus(name: name, symbol: symbol, on: on), for: 3) }
            }
        }
        DeviceMonitor.shared.start()

        // While the Mac is locked the island shows a lock, which opens as you unlock.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.isLocked = true
            self?.refresh()
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let showedLock = primary?.isLock == true
            isLocked = false
            if showedLock { show(.lock(open: true), for: 0.9) } else { refresh() }
        }

        // A new time zone, as after a flight: a moment saying where you are and how far that is from home, then
        // home's time waits in the circle.
        HomeTime.rememberHome()
        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                NSTimeZone.resetSystemTimeZone()
                guard let self else { return }
                refresh()
                guard setting(SettingsKey.islandHomeTime) else { return }
                let away = HomeTime.isAway
                show(.timeZone(city: HomeTime.city(away ? .current : HomeTime.zone), detail: away ? HomeTime.shortDifference() : "Home"), for: 5)
            }
            .store(in: &subscriptions)

        Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            self?.checkUpcomingEvents()
            // Reminders fall due and trips start as the clock moves on.
            self?.refresh()
        }
    }

    /// Events already announced, so each gets one "starting soon" alert.
    private var announcedEvents: Set<String> = []

    private func checkUpcomingEvents() {
        guard setting(SettingsKey.islandCalendar) else { return }
        let now = Date.now
        for event in CalendarStore.shared.events where !event.isAllDay {
            let minutes = event.startDate.timeIntervalSince(now) / 60
            let key = "\(event.calendarItemIdentifier)-\(event.startDate.timeIntervalSince1970)"
            guard minutes > 0, minutes <= 5, !announcedEvents.contains(key) else { continue }
            announcedEvents.insert(key)
            show(.event(title: event.title ?? "Event", start: event.startDate, color: event.calendar.color), for: 8)
        }
    }

    private func setting(_ key: String) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// Ongoing activities in priority order. The island shows the first, and the open card the second as an icon.
    private var ongoing: [IslandActivity] {
        var list: [IslandActivity] = []
        if setting(SettingsKey.islandMeetings), StatusMonitor.shared.meeting != nil { list.append(.meeting) }
        let timers = TimerStore.shared
        if setting(SettingsKey.islandTimers), timers.pomodoroRunning || timers.stopwatchRunning { list.append(.timer) }
        if setting(SettingsKey.islandTrips), TripStore.shared.trip != nil { list.append(.trip) }
        if setting(SettingsKey.islandMusic), NowPlayingStore.shared.track != nil { list.append(.music) }
        if setting(SettingsKey.islandReminders), !RemindersStore.shared.dueToday.isEmpty { list.append(.reminders) }
        if setting(SettingsKey.islandHotspot), StatusMonitor.shared.isOnHotspot { list.append(.hotspot) }
        if setting(SettingsKey.islandHomeTime), HomeTime.isAway { list.append(.homeTime) }
        if setting(SettingsKey.islandLock), isLocked { list.insert(.lock(open: false), at: 0) }
        return list
    }

    func refresh() {
        let list = ongoing
        let nextPrimary = transient ?? list.first
        let nextSecondary = transient == nil ? list.dropFirst().first : nil
        if primary != nextPrimary {
            if primary != nil, nextPrimary != nil, transient == nil { isExpanded = false }
            primary = nextPrimary
        }
        if secondary != nextSecondary { secondary = nextSecondary }
        if primary == nil || primary?.canExpand == false { isExpanded = false }
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "islandExpanded"), primary?.canExpand == true { isExpanded = true }
        #endif
    }

    /// Shows a brief activity over everything else, then returns to what was there.
    func show(_ activity: IslandActivity, for seconds: Double) {
        // Banners queue behind whatever brief thing is showing; quick status alerts replace each other.
        if let current = transient, current.isBanner || activity.isBanner {
            pending.append((activity, seconds))
            return
        }
        transientWork?.cancel()
        isExpanded = false
        transient = activity
        refresh()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            transient = nil
            if !pending.isEmpty {
                let (next, duration) = pending.removeFirst()
                show(next, for: duration)
            } else {
                refresh()
            }
        }
        transientWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Dismisses the current banner early, as when it is tapped.
    func dismissTransient() {
        transientWork?.perform()
    }

    // MARK: Geometry

    static var screen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private func updateNotch() {
        guard let screen = Self.screen else { return }
        if screen.safeAreaInsets.top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea
        {
            if !hasNotch { hasNotch = true }
            // Nudged by the fine tune in Notch Settings, for a notch measured a little off.
            let defaults = UserDefaults.standard
            let measured = CGSize(
                width: screen.frame.width - left.width - right.width + defaults.double(forKey: SettingsKey.notchWidthAdjust),
                height: screen.safeAreaInsets.top + defaults.double(forKey: SettingsKey.notchHeightAdjust)
            )
            if notch != measured { notch = measured }
        } else {
            if hasNotch { hasNotch = false }
            let standIn = CGSize(width: 190, height: NSStatusBar.system.thickness)
            if notch != standIn { notch = standIn }
        }
    }

    /// Height of the row that brief alerts add below the notch.
    static let dropHeight: CGFloat = 32

    /// How far a live activity reaches out on each side of the notch while closed, like the iPhone's
    /// compact island. The notch has no screen under it, so the artwork can only show beside it.
    static func wing(_ notch: CGSize) -> CGFloat { notch.height + 2 }

    /// Width of the open card and banners: wider than the notch, so their top row sits either side of it.
    var cardWidth: CGFloat { max(notch.width + 170, 360) }

    /// The circle for a second live activity, such as the hotspot while a song plays, beside the island on
    /// the right as on the iPhone, and the gap before it.
    var bubbleSize: CGFloat { notch.height }
    static let bubbleGap: CGFloat = 10

    /// Quiet status on its own, such as the hotspot, waits in the circle beside the notch, as on the iPhone,
    /// instead of widening the island. A Mac without a notch has nothing for it to sit beside, so there it keeps
    /// the island.
    var minorAlone: Bool { hasNotch && primary?.isMinor == true && secondary == nil }

    /// What the circle beside the island shows: a second live activity, or quiet status on its own.
    var bubbleActivity: IslandActivity? {
        if minorAlone, !isExpanded { return primary }
        return primary?.isTransient == false ? secondary : nil
    }

    var showsBubble: Bool { bubbleActivity != nil }

    /// Size of the black shape for the current state. With nothing live it is exactly the notch; a live
    /// activity sits either side of it at its height; brief alerts hang below it at its width; the open
    /// card and banners are wider.
    var size: CGSize {
        // On a Mac without a notch there is nothing to blend into, so the island only appears while
        // something is live.
        guard let primary else { return hasNotch ? notch : .zero }
        if minorAlone, !isExpanded { return notch }
        if primary.isBanner {
            return CGSize(width: bannerWidth(for: primary), height: notch.height + primary.expandedHeight)
        }
        if isExpanded {
            return CGSize(width: cardWidth, height: notch.height + primary.expandedHeight)
        }
        if primary.isTransient, !primary.isLock {
            return CGSize(width: notch.width, height: notch.height + Self.dropHeight)
        }
        return CGSize(width: notch.width + Self.wing(notch) * 2, height: notch.height)
    }

    /// A notification widens, when it needs to, so the app's full name fits beside the camera.
    private func bannerWidth(for activity: IslandActivity) -> CGFloat {
        guard case let .notification(item) = activity else { return cardWidth }
        if let width = bannerWidths[item.bundleID] { return width }
        let name = (item.appName as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold)]).width
        // Padding, icon and gap before the name, and room before the camera.
        let side = 16 + 20 + 6 + ceil(name) + 10
        let width = min(max(cardWidth, notch.width + side * 2), 640)
        bannerWidths[item.bundleID] = width
        return width
    }

    /// The size the island returns to when the open card closes.
    var closedSize: CGSize {
        guard let primary, !primary.isTransient else { return size }
        if minorAlone { return notch }
        return CGSize(width: notch.width + Self.wing(notch) * 2, height: notch.height)
    }

    /// The notch's own bottom corner radius, used when nothing is live.
    static let notchRadius: CGFloat = 10

    var bottomRadius: CGFloat {
        guard let primary else { return Self.notchRadius }
        if minorAlone, !isExpanded { return Self.notchRadius }
        if isExpanded || primary.isBanner { return 24 }
        return 16
    }
}

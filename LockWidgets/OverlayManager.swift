import AppKit
import SkyLightWindow
import SwiftUI

final class OverlayManager: ObservableObject {
    @Published private(set) var isShowing = false

    private var controllers: [NSWindowController] = []
    private let favoritesLayer = FavoritesClickLayer()

    init() {
        CalendarStore.shared.requestAccess()
        _ = LyricsStore.shared

        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            // After the free trial, the widgets wait for a licence key.
            guard UserDefaults.standard.object(forKey: SettingsKey.showOnLockScreen) as? Bool ?? true,
                  LicenseStore.shared.isActive
            else { return }
            self?.refreshData()
            self?.show(locked: true)
        }
        dnc.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.hide()
            // An app tapped in Favourite Apps on the lock screen opens now, as on the iPhone.
            self?.favoritesLayer.openWaitingApp()
        }

        #if DEBUG
        if UserDefaults.standard.bool(forKey: "previewAtLaunch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.show() }
        }
        #endif
    }

    /// Shows the widgets over every screen: on the lock screen when `locked`, otherwise as the desktop preview.
    func show(locked: Bool = false) {
        hide()
        for screen in NSScreen.screens {
            // The notch screen also gets a display-only copy of the Dynamic Island.
            let showsIsland = screen == IslandModel.screen
                && UserDefaults.standard.object(forKey: SettingsKey.islandEnabled) as? Bool ?? true
            let content = ZStack(alignment: .top) {
                WidgetBoard()
                if showsIsland { IslandView() }
            }
            let controller = SkyLightOperator.shared.delegateView(AnyView(content), toScreen: screen)
            // Full-screen overlay at the top level: let clicks pass through or the Mac becomes unusable.
            controller.window?.ignoresMouseEvents = true
            controllers.append(controller)
        }
        favoritesLayer.show(locked: locked)
        isShowing = true
    }

    func hide() {
        controllers.forEach { $0.close() }
        controllers.removeAll()
        favoritesLayer.hide()
        isShowing = false
    }

    /// The desktop preview: the same widgets over your desktop, with Favourite Apps clickable.
    func toggle() {
        if isShowing {
            hide()
        } else {
            show()
        }
    }

    func refreshData() {
        BatteryMonitor.shared.refresh()
        CalendarStore.shared.reload()
        RemindersStore.shared.reload()
        NewsStore.shared.refresh()
        WeatherStore.shared.refresh()
        NowPlayingStore.shared.poll()
    }
}

import AppKit
import Combine
import SwiftUI

/// The welcome that drops from the notch the first time Notchlight opens, the way a new Mac greets you. It is
/// one island in two steps: a short drop where "hello" writes itself, then it grows once into the welcome with
/// the ways to begin (buy, activate a licence or start the free trial). A second page shows what to try first.
/// It can be opened again from the menu's Help & Support and from the Licence page.
final class WelcomeController {
    static let shared = WelcomeController()

    private let model = WelcomeModel()
    private var panel: NSPanel?
    private var subscriptions: Set<AnyCancellable> = []
    /// Bumped on every show and close, so steps scheduled by an earlier one don't run.
    private var generation = 0

    private init() {
        LicenseStore.shared.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.model.licence = $0 }
            .store(in: &subscriptions)
        model.onBuy = { NSWorkspace.shared.open(URL(string: "https://notchlight.com/#plans")!) }
        model.onWebsite = { NSWorkspace.shared.open(URL(string: "https://notchlight.com/")!) }
        model.onActivate = { [weak self] in
            self?.close { NotificationCenter.default.post(name: AppDelegate.openPage, object: SettingsPage.licence) }
        }
        // The first time, the trial leads on to the Setup Guide, which picks the first widgets.
        model.onStart = { [weak self] in
            self?.close {
                if !UserDefaults.standard.bool(forKey: SettingsKey.hasLaunched) {
                    NotificationCenter.default.post(name: AppDelegate.openSettings, object: nil)
                }
            }
        }
        model.onPage = { [weak self] page in self?.go(to: page) }
    }

    var isShowing: Bool { panel?.isVisible == true }

    func show() {
        let island = IslandModel.shared
        LightController.shared.close()
        if panel == nil { makePanel() }
        generation += 1
        let current = generation
        model.notch = island.hasNotch ? island.notch : CGSize(width: 200, height: 0)
        model.page = .welcome
        model.isOpen = false
        model.helloProgress = 0
        model.showsText = false
        // One island at the notch: the live one steps aside while the welcome is out.
        IslandController.shared.isSuppressed = true
        place(model.helloSize)
        panel?.orderFrontRegardless()

        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        after(0.05, current) { [model] in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { model.isOpen = true }
        }
        let written = still ? 0.4 : 2.8
        if still {
            model.helloProgress = 1
        } else {
            after(0.45, current) { [model] in withAnimation(.timingCurve(0.45, 0, 0.35, 1, duration: 2.2)) { model.helloProgress = 1 } }
        }
        after(written, current) { [weak self, model] in
            self?.place(model.size(for: .welcome))
            withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { model.showsText = true }
        }
    }

    /// Folds the welcome back into the notch, then runs `next`.
    func close(then next: (() -> Void)? = nil) {
        guard isShowing else { next?(); return }
        generation += 1
        let current = generation
        withAnimation(.easeIn(duration: 0.15)) { model.showsText = false }
        withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) { model.isOpen = false }
        after(0.45, current) { [weak self] in
            self?.panel?.orderOut(nil)
            IslandController.shared.isSuppressed = false
            next?()
        }
    }

    private func go(to page: WelcomeModel.Page) {
        generation += 1
        let current = generation
        let from = model.size(for: model.page), to = model.size(for: page)
        // Big enough for both pages while the shape changes, then just the new page, so the panel never
        // covers more of the menu bar than it shows.
        place(CGSize(width: max(from.width, to.width), height: max(from.height, to.height)))
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { model.page = page }
        after(0.6, current) { [weak self] in self?.place(to) }
    }

    private func after(_ seconds: Double, _ current: Int, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.generation == current else { return }
            work()
        }
    }

    private func makePanel() {
        let panel = NSPanel.atNotch(level: .statusBar + 9)
        panel.contentView = NotchHostingView(rootView: WelcomeView(model: model))
        self.panel = panel
    }

    private func place(_ size: CGSize) {
        panel?.hang(size)
    }
}

extension NSPanel {
    /// A clear, borderless panel for shapes that hang from the notch, on every Space and over full-screen apps.
    /// One that takes the keyboard can be typed in without Notchlight coming to the front.
    static func atNotch(level: NSWindow.Level, takesKeyboard: Bool = false) -> NSPanel {
        let frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        let style: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        let panel = takesKeyboard
            ? KeyboardPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
            : NSPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = level
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        return panel
    }

    /// Hangs the panel from the top of the screen, centred on the notch.
    func hang(_ size: CGSize) {
        guard let screen = IslandModel.screen else { return }
        let frame = screen.frame
        setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}

/// A borderless panel that can become key, so its text fields take typing.
final class KeyboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Buttons on the notch work on the first click, while another app is in front.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

final class WelcomeModel: ObservableObject {
    enum Page { case welcome, tutorial }

    @Published var page: Page = .welcome
    /// Out of the notch; closed, the shape is the notch itself.
    @Published var isOpen = false
    /// How much of "hello" is written.
    @Published var helloProgress: CGFloat = 0
    /// The welcome under "hello", which the island grows to show once "hello" is written.
    @Published var showsText = false
    @Published var licence: LicenseStore.State = .trial(daysLeft: LicenseStore.trialDays)
    var notch = CGSize(width: 200, height: 32)

    var onBuy: () -> Void = {}
    var onActivate: () -> Void = {}
    var onStart: () -> Void = {}
    var onWebsite: () -> Void = {}
    var onPage: (Page) -> Void = { _ in }

    /// The first, short drop, just big enough for "hello".
    var helloSize: CGSize { CGSize(width: 320, height: notch.height + 104) }

    func size(for page: Page) -> CGSize {
        switch page {
        case .welcome: CGSize(width: 380, height: notch.height + (licence == .licensed ? 206 : 246))
        case .tutorial: CGSize(width: 740, height: notch.height + 214)
        }
    }

    var size: CGSize {
        guard isOpen else { return notch }
        return page == .welcome && !showsText ? helloSize : size(for: page)
    }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        let size = model.size
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: model.isOpen ? 28 : IslandModel.notchRadius)
                .fill(Color.black)
            VStack(spacing: 0) {
                // The camera.
                Color.clear.frame(height: model.notch.height)
                switch model.page {
                case .welcome: welcome.transition(.opacity)
                case .tutorial: tutorial.transition(.opacity)
                }
            }
            .frame(width: model.size(for: model.page).width)
            .opacity(model.isOpen ? 1 : 0)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipShape(IslandShape(bottomRadius: model.isOpen ? 28 : IslandModel.notchRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 0) {
            // Written in the middle of the short drop, then smaller at the top of the welcome.
            HelloShape()
                .trim(from: 0, to: model.helloProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: model.showsText ? 3.2 : 3.8, lineCap: .round, lineJoin: .round))
                .frame(width: model.showsText ? 120 : 164, height: model.showsText ? 48 : 66)
                .padding(.top, model.showsText ? 6 : 16)
                .padding(.bottom, 8)

            VStack(spacing: 0) {
                Text("Welcome to Notchlight!")
                    .font(.system(size: 15, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, 3)

                if model.licence == .licensed {
                    Button(action: model.onStart) {
                        Label("Get Started", systemImage: "arrow.right")
                    }
                    .buttonStyle(WelcomeButtonStyle(prominent: true))
                    .padding(.top, 14)
                } else {
                    Button(action: model.onBuy) {
                        Label("Choose a Plan", systemImage: "arrow.up.right")
                            .frame(width: 196)
                    }
                    .buttonStyle(WelcomeButtonStyle(prominent: true))
                    .padding(.top, 14)

                    HStack(spacing: 8) {
                        Button(action: model.onActivate) {
                            Label("Activate Licence", systemImage: "key.horizontal")
                        }
                        if case let .trial(daysLeft) = model.licence {
                            Button(action: model.onStart) {
                                Label(daysLeft >= LicenseStore.trialDays ? "Start \(LicenseStore.trialDays)-Day Trial" : "Continue Trial", systemImage: "clock")
                            }
                        }
                    }
                    .buttonStyle(WelcomeButtonStyle(prominent: false))
                    .padding(.top, 9)
                }

                Button("See Tutorial") { model.onPage(.tutorial) }
                    .buttonStyle(WelcomeLinkStyle(size: 13))
                    .padding(.top, 13)
                Button("notchlight.com", action: model.onWebsite)
                    .buttonStyle(WelcomeLinkStyle(size: 12))
                    .padding(.top, 7)
            }
            .opacity(model.showsText ? 1 : 0)
        }
    }

    private var subtitle: String {
        switch model.licence {
        case .licensed: "Notchlight is yours on this Mac. Thank you!"
        case .expired: "Your free trial has ended. Buy Notchlight to keep it."
        case let .trial(daysLeft) where daysLeft < LicenseStore.trialDays: "Your free trial has \(daysLeft == 1 ? "1 day" : "\(daysLeft) days") left."
        case .trial: "Widgets on your lock screen, an island at your notch."
        }
    }

    private static let tips: [(symbol: String, text: String)] = [
        ("cursorarrow.rays", "Point at the island for the song, its lyrics and controls."),
        ("cursorarrow.click.2", "Click the notch for Light: music, calendar, notes, timers and to-dos."),
        ("lock.laptopcomputer", "Press ⌃⌘Q to lock your Mac and see your widgets."),
        ("rectangle.3.group", "Arrange your widgets in Layout Studio, from the menu bar."),
    ]

    private var tutorial: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Self.tips, id: \.symbol) { tip in
                    VStack(spacing: 14) {
                        Image(systemName: tip.symbol)
                            .font(.system(size: 40, weight: .ultraLight))
                            .frame(height: 52)
                        Text(tip.text)
                            .font(.system(size: 13))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 150)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)

            HStack(spacing: 12) {
                Button { model.onPage(.welcome) } label: {
                    Label("Back to Welcome", systemImage: "chevron.left")
                }
                .buttonStyle(WelcomeLinkStyle(size: 13))
                if model.licence == .licensed {
                    Button(action: model.onStart) { Label("Get Started", systemImage: "arrow.right") }
                        .buttonStyle(WelcomeButtonStyle(prominent: true))
                } else {
                    Button(action: model.onBuy) { Label("Choose a Plan", systemImage: "arrow.up.right") }
                        .buttonStyle(WelcomeButtonStyle(prominent: true))
                    if case let .trial(daysLeft) = model.licence {
                        Button(action: model.onStart) {
                            Label(daysLeft >= LicenseStore.trialDays ? "Start \(LicenseStore.trialDays)-Day Trial" : "Continue Trial", systemImage: "clock")
                        }
                        .buttonStyle(WelcomeButtonStyle(prominent: false))
                    }
                }
            }
            .padding(.top, 22)
        }
    }
}

/// The blue capsule, and the grey keys beside it.
private struct WelcomeButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, prominent ? 16 : 12)
            .frame(height: prominent ? 30 : 28)
            .background {
                if prominent {
                    Capsule().fill(Color(red: 0.25, green: 0.55, blue: 1))
                } else {
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Grey words that work as links.
private struct WelcomeLinkStyle: ButtonStyle {
    var size: CGFloat = 13

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size))
            .foregroundStyle(.white.opacity(configuration.isPressed ? 0.85 : 0.55))
            .contentShape(Rectangle())
    }
}

/// "hello" in one continuous stroke of the pen, to be written with `.trim`.
struct HelloShape: Shape {
    /// The stroke's extent in the coordinates of the curves below.
    private static let box = CGRect(x: 14, y: 6, width: 390, height: 156)
    private static let start = CGPoint(x: 22, y: 150)
    /// Each curve's two control points and its end, as (x, y) pairs.
    private static let curves: [[CGFloat]] = [
        // h: up into the loop, down the stem, over the arch and out
        [50, 140, 92, 80, 98, 48], [104, 18, 86, 10, 78, 24], [66, 46, 62, 110, 58, 150],
        [62, 128, 80, 104, 98, 106], [116, 108, 114, 140, 120, 148], [124, 156, 140, 150, 152, 140],
        // e
        [166, 130, 190, 118, 188, 106], [186, 94, 162, 98, 158, 118], [154, 140, 168, 154, 186, 150],
        [200, 147, 214, 132, 222, 118],
        // l
        [236, 92, 252, 40, 246, 24], [240, 8, 222, 18, 222, 44], [222, 80, 222, 130, 232, 146],
        [240, 156, 256, 148, 266, 132],
        // l
        [280, 104, 294, 44, 288, 26], [282, 10, 264, 20, 264, 46], [264, 82, 264, 132, 274, 146],
        [282, 156, 296, 150, 306, 138],
        // o, and the flourish out of it
        [314, 124, 322, 106, 340, 104], [360, 102, 368, 126, 358, 142], [348, 156, 322, 154, 320, 138],
        [318, 120, 336, 104, 352, 106], [366, 108, 380, 112, 396, 104],
    ]

    func path(in rect: CGRect) -> Path {
        let box = Self.box
        let scale = min(rect.width / box.width, rect.height / box.height)
        let origin = CGPoint(x: rect.midX - box.width * scale / 2, y: rect.midY - box.height * scale / 2)
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: origin.x + (x - box.minX) * scale, y: origin.y + (y - box.minY) * scale)
        }
        var path = Path()
        path.move(to: point(Self.start.x, Self.start.y))
        for c in Self.curves {
            path.addCurve(to: point(c[4], c[5]), control1: point(c[0], c[1]), control2: point(c[2], c[3]))
        }
        return path
    }
}

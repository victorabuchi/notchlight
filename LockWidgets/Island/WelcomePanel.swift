import AppKit
import Combine
import SwiftUI

/// The welcome that drops from the notch the first time Notchlight opens, the way a new Mac greets you: "hello"
/// writes itself, then the ways to begin (buy, activate a licence or start the free trial). A second page shows
/// what to try first. It can be opened again from the menu's Help & Support and from the Licence page.
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
        model.onBuy = { NSWorkspace.shared.open(LicenseStore.checkoutURL) }
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
        if panel == nil { makePanel() }
        generation += 1
        let current = generation
        model.notch = island.hasNotch ? island.notch : CGSize(width: 200, height: 0)
        model.page = .welcome
        model.isOpen = false
        model.helloProgress = 0
        model.showsText = false
        place(model.size(for: .welcome))
        panel?.orderFrontRegardless()

        let still = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        after(0.05, current) { [model] in
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) { model.isOpen = true }
        }
        if still {
            model.helloProgress = 1
            after(0.3, current) { [model] in withAnimation(.easeOut(duration: 0.4)) { model.showsText = true } }
        } else {
            after(0.5, current) { [model] in withAnimation(.timingCurve(0.45, 0, 0.35, 1, duration: 2.3)) { model.helloProgress = 1 } }
            after(2.8, current) { [model] in withAnimation(.spring(response: 0.6, dampingFraction: 0.86)) { model.showsText = true } }
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
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: model.size(for: .welcome)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above the island, which it grows out of.
        panel.level = .statusBar + 9
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.contentView = FirstClickView(rootView: WelcomeView(model: model))
        self.panel = panel
    }

    /// Hangs the panel from the top of the screen, centred on the notch.
    private func place(_ size: CGSize) {
        guard let panel, let screen = IslandModel.screen else { return }
        let frame = screen.frame
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }
}

/// Buttons in the welcome work on the first click, while another app is in front.
private final class FirstClickView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for _: NSEvent?) -> Bool { true }
}

final class WelcomeModel: ObservableObject {
    enum Page { case welcome, tutorial }

    @Published var page: Page = .welcome
    /// Out of the notch; closed, the shape is the notch itself.
    @Published var isOpen = false
    /// How much of "hello" is written.
    @Published var helloProgress: CGFloat = 0
    /// The words and buttons under "hello", which arrive once it's written.
    @Published var showsText = false
    @Published var licence: LicenseStore.State = .trial(daysLeft: LicenseStore.trialDays)
    var notch = CGSize(width: 200, height: 32)

    var onBuy: () -> Void = {}
    var onActivate: () -> Void = {}
    var onStart: () -> Void = {}
    var onWebsite: () -> Void = {}
    var onPage: (Page) -> Void = { _ in }

    func size(for page: Page) -> CGSize {
        switch page {
        case .welcome: CGSize(width: 440, height: notch.height + 334)
        case .tutorial: CGSize(width: 800, height: notch.height + 238)
        }
    }

    var size: CGSize { isOpen ? size(for: page) : notch }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeModel

    var body: some View {
        let size = model.size
        ZStack(alignment: .top) {
            IslandShape(bottomRadius: model.isOpen ? 34 : IslandModel.notchRadius)
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
        .clipShape(IslandShape(bottomRadius: model.isOpen ? 34 : IslandModel.notchRadius))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    // MARK: Pages

    private var welcome: some View {
        VStack(spacing: 0) {
            HelloShape()
                .trim(from: 0, to: model.helloProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 176, height: 72)
                // Written large in the middle, then it settles at the top as the welcome arrives.
                .scaleEffect(model.showsText ? 1 : 1.3)
                .offset(y: model.showsText ? 0 : 92)
                .padding(.top, 16)
                .padding(.bottom, 12)

            VStack(spacing: 0) {
                Text("Welcome to Notchlight!")
                    .font(.system(size: 16, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.72))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)

                Button(action: model.licence == .licensed ? model.onStart : model.onBuy) {
                    Label(model.licence == .licensed ? "Get Started" : "Buy Notchlight", systemImage: model.licence == .licensed ? "arrow.right" : "arrow.up.right")
                        .frame(width: 236)
                }
                .buttonStyle(WelcomeButtonStyle(prominent: true))
                .padding(.top, 18)

                if model.licence != .licensed {
                    HStack(spacing: 10) {
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
                    .padding(.top, 12)
                }

                Button("See Tutorial") { model.onPage(.tutorial) }
                    .buttonStyle(WelcomeLinkStyle())
                    .padding(.top, 16)
                Button("notchlight.com", action: model.onWebsite)
                    .buttonStyle(WelcomeLinkStyle(size: 13))
                    .padding(.top, 10)
            }
            .opacity(model.showsText ? 1 : 0)
            .offset(y: model.showsText ? 0 : 10)
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
        ("cursorarrow.click.2", "Click the island to open the app behind it."),
        ("lock.display", "Press ⌃⌘Q to lock your Mac and see your widgets."),
        ("rectangle.3.group", "Arrange your widgets in Layout Studio, from the menu bar."),
    ]

    private var tutorial: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Self.tips, id: \.symbol) { tip in
                    VStack(spacing: 16) {
                        Image(systemName: tip.symbol)
                            .font(.system(size: 46, weight: .ultraLight))
                            .frame(height: 58)
                        Text(tip.text)
                            .font(.system(size: 14))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 164)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)

            HStack(spacing: 14) {
                Button { model.onPage(.welcome) } label: {
                    Label("Back to Welcome", systemImage: "chevron.left")
                }
                .buttonStyle(WelcomeLinkStyle(size: 14))
                if model.licence == .licensed {
                    Button(action: model.onStart) { Label("Get Started", systemImage: "arrow.right") }
                        .buttonStyle(WelcomeButtonStyle(prominent: true))
                } else {
                    Button(action: model.onBuy) { Label("Buy Notchlight", systemImage: "arrow.up.right") }
                        .buttonStyle(WelcomeButtonStyle(prominent: true))
                    if case let .trial(daysLeft) = model.licence {
                        Button(action: model.onStart) {
                            Label(daysLeft >= LicenseStore.trialDays ? "Start \(LicenseStore.trialDays)-Day Trial" : "Continue Trial", systemImage: "clock")
                        }
                        .buttonStyle(WelcomeButtonStyle(prominent: false))
                    }
                }
            }
            .padding(.top, 26)
        }
    }
}

/// The blue capsule, and the grey keys beside it.
private struct WelcomeButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: prominent ? 15 : 14, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, prominent ? 20 : 14)
            .frame(height: prominent ? 38 : 32)
            .background {
                if prominent {
                    Capsule().fill(Color(red: 0.25, green: 0.55, blue: 1))
                } else {
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.14))
                }
            }
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Grey words that work as links.
private struct WelcomeLinkStyle: ButtonStyle {
    var size: CGFloat = 14

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

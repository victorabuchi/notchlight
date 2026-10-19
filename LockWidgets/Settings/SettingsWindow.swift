import SwiftUI

enum SettingsPage: Hashable {
    case general, whatsNew, licence, layoutStudio, gallery, appearance, stickyNotes, island, notch, about
    case widget(WidgetKind)

    #if DEBUG
    /// `-settingsPage layout` (or a widget name) opens settings on that page, for screenshots.
    static var launchPage: SettingsPage? {
        guard let name = UserDefaults.standard.string(forKey: "settingsPage") else { return nil }
        if let kind = WidgetKind(rawValue: name) { return .widget(kind) }
        return ["general": .general, "whatsnew": .whatsNew, "licence": .licence, "studio": .layoutStudio, "gallery": .gallery, "appearance": .appearance, "notes": .stickyNotes, "island": .island, "notch": .notch, "about": .about][name]
    }
    #endif
}

/// Which settings page is showing, so the menu bar can open a specific one.
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    @Published var page: SettingsPage? = .general
}

struct SettingsWindow: View {
    @ObservedObject var overlay: OverlayManager
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        NavigationSplitView {
            List(selection: $router.page) {
                SidebarRow(title: "General", symbol: "gearshape.fill", color: .gray)
                    .tag(SettingsPage.general)
                SidebarRow(title: "What's New", symbol: "sparkles", color: .pink)
                    .tag(SettingsPage.whatsNew)
                SidebarRow(title: "Licence", symbol: "key.fill", color: .orange)
                    .tag(SettingsPage.licence)

                Section("Lock Screen") {
                    SidebarRow(title: "Layout Studio", symbol: "rectangle.3.group.fill", color: .blue)
                        .tag(SettingsPage.layoutStudio)
                    SidebarRow(title: "Layout Gallery", symbol: "square.grid.2x2.fill", color: .indigo)
                        .tag(SettingsPage.gallery)
                    SidebarRow(title: "Appearance", symbol: "paintpalette.fill", color: .teal)
                        .tag(SettingsPage.appearance)
                    SidebarRow(title: "Sticky Notes", symbol: "note.text", color: .yellow)
                        .tag(SettingsPage.stickyNotes)
                }

                Section("Desktop") {
                    SidebarRow(title: "Dynamic Island", symbol: "capsule.fill", color: .black)
                        .tag(SettingsPage.island)
                    SidebarRow(title: "Notch", symbol: "macbook", color: .blue)
                        .tag(SettingsPage.notch)
                }

                Section("Widget Settings") {
                    ForEach(WidgetKind.settingsKinds) { kind in
                        SidebarRow(title: kind.title, symbol: kind.symbol, color: kind.color)
                            .tag(SettingsPage.widget(kind))
                    }
                }

                Section {
                    SidebarRow(title: "About", symbol: "info.circle.fill", color: .indigo)
                        .tag(SettingsPage.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            switch router.page ?? .general {
            case .general: GeneralPage(overlay: overlay)
            case .whatsNew: WhatsNewPage()
            case .licence: LicensePage()
            case .layoutStudio: LayoutStudioPage()
            case .gallery: LayoutGalleryPage()
            case .appearance: AppearancePage()
            case .stickyNotes: StickyNotesPage()
            case .island: IslandSettingsPage()
            case .notch: NotchSettingsView(embedded: true)
            case .about: AboutPage()
            case let .widget(kind): WidgetPage(kind: kind)
            }
        }
        .frame(minWidth: 1000, minHeight: 640)
        .onAppear {
            #if DEBUG
            if let launchPage = SettingsPage.launchPage { router.page = launchPage }
            let width = UserDefaults.standard.double(forKey: "windowWidth")
            if width > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApp.windows.first { $0.title == "Notchlight" }?.setContentSize(NSSize(width: width, height: 760))
                }
            }
            #endif
            DockPolicy.update()
        }
        .onDisappear {
            DockPolicy.update()
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let symbol: String
    let color: Color

    var body: some View {
        Label {
            Text(title)
        } icon: {
            SidebarIcon(symbol: symbol, color: color)
        }
        .padding(.vertical, 2)
    }
}

/// A sidebar page's icon: a white symbol on a rounded tile of its colour.
struct SidebarIcon: View {
    let symbol: String
    let color: Color

    var body: some View {
        // Fit every symbol into the same inner box so wide ones (battery) stay centred.
        Image(systemName: symbol)
            .resizable()
            .symbolVariant(.fill)
            .scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .frame(width: 13, height: 13)
            .frame(width: 22, height: 22)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

// MARK: Shared page pieces

/// Lock-screen-like backdrop for live widget previews.
struct PreviewStage<Content: View>: View {
    var height: CGFloat = 280
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            LockScreenBackdrop()
            content
                .environment(\.isWidgetPreview, true)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct LockScreenBackdrop: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.36, green: 0.27, blue: 0.75), Color(red: 0.12, green: 0.1, blue: 0.38)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [Color(red: 0.75, green: 0.55, blue: 1).opacity(0.55), .clear],
                center: .init(x: 0.2, y: 0.3),
                startRadius: 0,
                endRadius: 420
            )
        }
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
            Text(subtitle)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SliderValue: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: (Double) -> String

    var body: some View {
        HStack {
            Slider(value: $value, in: range, step: step)
                .frame(minWidth: 160)
            Text(label(value))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
        }
    }
}

import ServiceManagement
import SwiftUI

/// Which Notch Settings tab is showing, so Light's gear and the menu can open a particular one.
final class NotchSettingsRouter: ObservableObject {
    static let shared = NotchSettingsRouter()
    @Published var tab: NotchTab = .general
}

enum NotchTab: Hashable {
    case general, liquid, gestures, activities, light, tray, dropArea, licence, about
}

/// The notch's own settings window, with its tabs along the top as macOS settings windows have them: the
/// island's behaviour, Liquid Glass, gestures, live activities, Light, the Tray, the drop area, the licence.
struct NotchSettingsView: View {
    @ObservedObject private var router = NotchSettingsRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            NotchGeneralTab()
                .tabItem { Label("General", systemImage: "gearshape.fill") }
                .tag(NotchTab.general)
            LiquidTab()
                .tabItem { Label("Liquid", systemImage: "drop.fill") }
                .tag(NotchTab.liquid)
            GesturesTab()
                .tabItem { Label("Gestures", systemImage: "hand.point.up.left.fill") }
                .tag(NotchTab.gestures)
            Form { IslandActivitySettings() }
                .formStyle(.grouped)
                .frame(height: 560)
                .tabItem { Label("Live Activities", systemImage: "dot.radiowaves.left.and.right") }
                .tag(NotchTab.activities)
            LightTab()
                .tabItem { Label("Light", systemImage: "lamp.desk.fill") }
                .tag(NotchTab.light)
            TrayTab()
                .tabItem { Label("Tray", systemImage: "tray.fill") }
                .tag(NotchTab.tray)
            DropAreaTab()
                .tabItem { Label("Drop Area", systemImage: "square.on.square.dashed") }
                .tag(NotchTab.dropArea)
            LicensePage(showsHeader: false)
                .frame(height: 560)
                .tabItem { Label("Licence", systemImage: "key.horizontal.fill") }
                .tag(NotchTab.licence)
            AboutPage()
                .frame(height: 330)
                .tabItem { Label("About", systemImage: "ellipsis.circle.fill") }
                .tag(NotchTab.about)
        }
        .frame(width: 660)
        .onAppear { DockPolicy.update() }
        .onDisappear { DockPolicy.update() }
    }
}

/// A checkbox with its explanation underneath, as macOS settings lay them out.
private struct Check: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    init(_ title: String, _ detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Toggle(title, isOn: $isOn)
            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 20)
            }
        }
    }
}

/// A slider with its value beside it.
private struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(Int($0)) }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .frame(width: 52, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(format(value))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
    }
}

/// The columns layout macOS settings use: names on the left, controls on the right.
private struct TabForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form { content }
            .formStyle(.columns)
            .padding(.horizontal, 36)
            .padding(.vertical, 26)
            .frame(maxWidth: .infinity)
    }
}

// MARK: Tabs

private struct NotchGeneralTab: View {
    @AppStorage(SettingsKey.islandEnabled) private var enabled = true
    @AppStorage(SettingsKey.islandHoverOpens) private var hoverOpens = true
    @AppStorage(SettingsKey.notchWidthAdjust) private var width = 0.0
    @AppStorage(SettingsKey.notchHeightAdjust) private var height = 0.0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabForm {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, on in
                    try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                }
            Divider()
            LabeledContent("Dynamic Island:") {
                VStack(alignment: .leading, spacing: 10) {
                    Check("Show the Dynamic Island", isOn: $enabled)
                    Check("Open when you point at it", "Resting the pointer on a live activity opens its card. When this is off, swipe down on it instead.", isOn: $hoverOpens)
                }
            }
            LabeledContent("Notch fine tune:") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Notchlight measures your notch, but if the island looks a little off, nudge it here so it lines up exactly.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    ValueSlider(title: "Width", value: $width, range: -20 ... 20)
                    ValueSlider(title: "Height", value: $height, range: -10 ... 10)
                }
                .frame(maxWidth: 380, alignment: .leading)
            }
            Divider()
            LabeledContent("Others:") {
                HStack {
                    Button("Show the Welcome Again") { WelcomeController.shared.show() }
                    Button("Reset Notch Settings") { reset() }
                }
            }
        }
    }

    private func reset() {
        let keys = [
            SettingsKey.islandHoverOpens, SettingsKey.notchWidthAdjust, SettingsKey.notchHeightAdjust, SettingsKey.gestures,
            SettingsKey.gestureOpenClose, SettingsKey.gestureMedia, SettingsKey.gestureInvert, SettingsKey.liquidGlass,
            SettingsKey.liquidTint, SettingsKey.liquidClear, SettingsKey.lightEnabled, SettingsKey.lightOnHover,
            SettingsKey.lightMirror, SettingsKey.trayOpensWithFiles, SettingsKey.dropArea, SettingsKey.dropAirDrop,
        ]
        keys.forEach(UserDefaults.standard.removeObject(forKey:))
    }
}

private struct LiquidTab: View {
    @AppStorage(SettingsKey.liquidGlass) private var liquid = false
    @AppStorage(SettingsKey.liquidTint) private var tint = 0.45
    @AppStorage(SettingsKey.liquidClear) private var clear = false

    private var note: String {
        if #available(macOS 26, *) {
            return "Light and the island's open cards turn to Liquid Glass, with your desktop showing through. The closed island stays black, as the notch it sits in is."
        }
        return "Light and the island's open cards turn to frosted glass. Real Liquid Glass needs macOS 26 or later. The closed island stays black, as the notch it sits in is."
    }

    var body: some View {
        TabForm {
            Check("Enable Liquid Glass", note, isOn: $liquid)
            Divider()
            LabeledContent("Glass:") {
                Picker("Glass", selection: $clear) {
                    Text("Regular").tag(false)
                    Text("Clear").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 200)
            }
            .disabled(!liquid)
            LabeledContent("Tint:") {
                VStack(alignment: .leading, spacing: 4) {
                    ValueSlider(title: "Dark", value: $tint, range: 0 ... 0.9, step: 0.05) { "\(Int(($0 * 100).rounded()))%" }
                        .frame(maxWidth: 380)
                    Text("A darker tint keeps white text easy to read over bright windows.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!liquid)
        }
    }
}

private struct GesturesTab: View {
    @AppStorage(SettingsKey.gestures) private var gestures = true
    @AppStorage(SettingsKey.gestureOpenClose) private var openClose = true
    @AppStorage(SettingsKey.gestureMedia) private var media = true
    @AppStorage(SettingsKey.gestureInvert) private var invert = false

    var body: some View {
        TabForm {
            Check("Allow gestures when pointing at the notch", "Two fingers on the trackpad, with the pointer on the island or in Light.", isOn: $gestures)
            Check("Open and close with vertical swipes", "Swipe down to open Light, or the card of what's live; swipe up to close it.", isOn: $openClose)
                .disabled(!gestures)
            Check("Change songs with horizontal swipes", isOn: $media)
                .disabled(!gestures)
            Check("Invert song swipes", "When on, a left swipe plays the next song; when off, the previous one.", isOn: $invert)
                .disabled(!gestures || !media)
        }
    }
}

private struct LightTab: View {
    @AppStorage(SettingsKey.lightEnabled) private var light = true
    @AppStorage(SettingsKey.lightOnHover) private var onHover = false
    @AppStorage(SettingsKey.lightMirror) private var mirror = true

    var body: some View {
        TabForm {
            Check("Enable Light", "Click the notch to open Light: the song that's playing with its lyric and controls, a mirror from your camera, and the Tray. A click on a live activity still opens its app.", isOn: $light)
            Divider()
            Check("Open when you point at the notch", "Light drops down as the pointer rests on the empty notch, without a click.", isOn: $onHover)
                .disabled(!light)
            Check("Show the mirror", "A circle that shows your camera when you click it, to check how you look before a call. The camera turns off when Light closes.", isOn: $mirror)
                .disabled(!light)
        }
    }
}

private struct TrayTab: View {
    @AppStorage(SettingsKey.trayOpensWithFiles) private var opensWithFiles = true
    @ObservedObject private var tray = TrayStore.shared

    var body: some View {
        TabForm {
            Check("Open the Tray when files are in it", "Light opens on the Tray while it holds files. You can still switch to Light.", isOn: $opensWithFiles)
            Divider()
            LabeledContent("In the Tray:") {
                HStack {
                    Text(tray.files.isEmpty ? "Nothing yet" : tray.files.count == 1 ? "1 file" : "\(tray.files.count) files")
                    Button("Empty the Tray") { tray.clear() }
                        .disabled(tray.files.isEmpty)
                }
            }
            Text("The Tray keeps a link to each file, not a copy. Files stay where they are until you drag them out of the Tray to wherever you drop them.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct DropAreaTab: View {
    @AppStorage(SettingsKey.dropArea) private var dropArea = true
    @AppStorage(SettingsKey.dropAirDrop) private var airDrop = true

    var body: some View {
        TabForm {
            Check("Drop files on the notch", "Drag files to the notch and Light opens with places to drop them.", isOn: $dropArea)
            Check("AirDrop", "Drop files on AirDrop to send them to a nearby iPhone, iPad or Mac.", isOn: $airDrop)
                .disabled(!dropArea)
        }
    }
}

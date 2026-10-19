import AppKit
import CoreAudio
import CoreMediaIO
import CoreWLAN
import Darwin

/// Hotspot, calls and meetings: system states the island shows while they last.
final class StatusMonitor: ObservableObject {
    static let shared = StatusMonitor()

    /// Network name when the Mac is joined to an iPhone's Personal Hotspot.
    @Published private(set) var hotspot: String?
    @Published private(set) var isOnHotspot = false

    struct Meeting: Equatable {
        let app: String
        let bundleID: String?
        let started: Date
        var microphone: Bool
        var camera: Bool

        /// What the island calls it, such as "Zoom Meeting" or "FaceTime Call".
        var title: String {
            switch app {
            case "Zoom": "Zoom Meeting"
            case "Google Meet": "Google Meet"
            default: "\(app) Call"
            }
        }
    }

    @Published private(set) var meeting: Meeting?

    /// What the dot beside the island shows: the screen being recorded or shared comes first, then the camera,
    /// then the microphone.
    enum Privacy: Equatable {
        case microphone, camera, screenRecording
    }

    @Published private(set) var privacy: Privacy?

    private var timer: Timer?
    private let queue = DispatchQueue(label: "LockWidgets.Status")

    private init() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    /// The Wi-Fi, audio and process checks make blocking system calls, so they run off the main thread.
    private func poll() {
        queue.async { [weak self] in
            guard let self else { return }
            let onHotspot = Self.ipv4Addresses().contains { $0.hasPrefix("172.20.10.") }
            let name = onHotspot ? (CWWiFiClient.shared().interface()?.ssid() ?? "iPhone") : nil
            let listening = Self.appsUsingMicrophone()
            let camera = Self.cameraInUse()
            let screenRecording = Self.screenWatcherPresent?() ?? false
            let zoomMeeting = Self.processRunning("CptHost")
            let call = zoomMeeting ? nil : Self.call(listening: listening)
            DispatchQueue.main.async {
                self.apply(onHotspot: onHotspot, name: name, listening: listening, camera: camera, screenRecording: screenRecording, zoomMeeting: zoomMeeting, call: call)
            }
        }
    }

    private func apply(onHotspot: Bool, name: String?, listening: [String], camera: Bool, screenRecording: Bool, zoomMeeting: Bool, call: (name: String, bundleID: String?)?) {
        // iPhone hotspots hand out addresses in 172.20.10.0/28.
        if onHotspot != isOnHotspot { isOnHotspot = onHotspot }
        if name != hotspot { hotspot = name }

        // Zoom runs its meeting in a separate CptHost process, so its presence means a meeting is on.
        var next: Meeting?
        if zoomMeeting {
            let microphone = listening.contains { $0.hasPrefix("us.zoom") }
            next = Meeting(app: "Zoom", bundleID: "us.zoom.xos", started: meeting?.app == "Zoom" ? meeting!.started : .now, microphone: microphone, camera: camera)
        } else if let call {
            next = Meeting(app: call.name, bundleID: call.bundleID, started: meeting?.app == call.name ? meeting!.started : .now, microphone: true, camera: camera)
        }
        if next != meeting { meeting = next }

        let users = listening.filter(Self.isVisibleApp)
        let dot: Privacy? = screenRecording ? .screenRecording
            : camera ? .camera
            : users.isEmpty ? nil : .microphone
        if dot != privacy { privacy = dot }
    }

    /// Listeners that are always on, such as "Hey Siri"; macOS shows no dot for them either.
    private static let backgroundListeners = ["com.apple.corespeechd", "com.apple.siri", "com.apple.assistantd", "com.apple.SpeechRecognitionCore"]

    /// Whether a process recording from a microphone is an app you can see, or a call app's or browser's
    /// helper, as macOS's own indicator counts it. System listeners such as Siri, Sound Recognition or Live
    /// Captions keep the input running in the background without anything showing, so they don't count.
    private static func isVisibleApp(_ process: String) -> Bool {
        if backgroundListeners.contains(where: { process.hasPrefix($0) }) { return false }
        if callApps.contains(where: { process.hasPrefix($0.bundleID) }) { return true }
        return NSWorkspace.shared.runningApplications.contains { app in
            guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
            return process == id || process.hasPrefix(id + ".")
        }
    }

    /// Whether anything is recording or sharing the screen. SkyLight is private, but this is the check macOS
    /// itself offers, and it covers screenshots' screen recording, QuickTime, screen sharing and meeting apps.
    private static let screenWatcherPresent: (@convention(c) () -> Bool)? = {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
              let symbol = dlsym(handle, "SLSIsScreenWatcherPresent")
        else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)
    }()

    /// Calls and meeting apps that may be using the mic or camera, most specific first. Browsers record
    /// from helper processes: Chrome's helpers share its identifier, Firefox records from its content
    /// processes and Safari from WebKit's.
    private static let callApps: [(bundleID: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.microsoft.teams2", "Teams"),
        ("com.microsoft.teams", "Teams"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("com.hnc.Discord", "Discord"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("com.google.Chrome", "Chrome"),
        ("org.mozilla", "Firefox"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit", "Safari"),
        ("com.microsoft.edgemac", "Edge"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.brave.Browser", "Brave"),
    ]

    /// Only a known call app or browser holding the microphone counts, so dictation or recording apps
    /// don't. A browser's call is named after the site when its window says so, such as Zoom on the web.
    private static func call(listening: [String]) -> (name: String, bundleID: String?)? {
        for app in callApps {
            guard let process = listening.first(where: { $0.hasPrefix(app.bundleID) }) else { continue }
            let owner = owningApp(of: process, family: app.bundleID)
            let site = owner.flatMap(webCallName)
            return (site ?? app.name, owner)
        }
        return nil
    }

    /// The app behind a process using the microphone, such as Chrome Canary for its helper.
    private static func owningApp(of process: String, family: String) -> String? {
        let apps = NSWorkspace.shared.runningApplications.compactMap { $0.activationPolicy == .regular ? $0.bundleIdentifier : nil }
        if let exact = apps.filter({ process.hasPrefix($0) }).max(by: { $0.count < $1.count }) { return exact }
        if family == "com.apple.WebKit" { return apps.first { $0 == "com.apple.Safari" } }
        return apps.first { $0.hasPrefix(family) }
    }

    /// Zoom, Google Meet or Teams when a browser window's title names it. Reading titles needs
    /// Accessibility; without it the call is named after the browser.
    private static func webCallName(bundleID: String) -> String? {
        guard AXIsProcessTrusted(), let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return nil }
        var windows: CFTypeRef?
        guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(app.processIdentifier), kAXWindowsAttribute as CFString, &windows) == .success,
              let list = windows as? [AXUIElement]
        else { return nil }
        for window in list {
            var title: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &title) == .success, let text = title as? String else { continue }
            if text.localizedCaseInsensitiveContains("zoom") { return "Zoom" }
            if text.hasPrefix("Meet") || text.localizedCaseInsensitiveContains("Google Meet") { return "Google Meet" }
            if text.localizedCaseInsensitiveContains("Teams") { return "Teams" }
        }
        return nil
    }


    // MARK: Zoom controls

    /// Sends one of Zoom's own shortcuts: ⌘⇧A toggles the microphone, ⌘⇧V the camera.
    static func sendZoomShortcut(_ key: CGKeyCode) {
        guard let zoom = NSRunningApplication.runningApplications(withBundleIdentifier: "us.zoom.xos").first else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = [.maskCommand, .maskShift]
            event?.postToPid(zoom.processIdentifier)
        }
    }

    static let zoomMuteKey: CGKeyCode = 0x00 // A
    static let zoomVideoKey: CGKeyCode = 0x09 // V

    // MARK: System probes

    private static func ipv4Addresses() -> [String] {
        var results: [String] = []
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0 else { return [] }
        defer { freeifaddrs(addresses) }
        var pointer = addresses
        while let entry = pointer?.pointee {
            if entry.ifa_addr?.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(entry.ifa_addr, socklen_t(entry.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    results.append(String(cString: host))
                }
            }
            pointer = entry.ifa_next
        }
        return results
    }

    private static func processRunning(_ name: String) -> Bool {
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(MemoryLayout<pid_t>.size * pids.count)))
        var buffer = [CChar](repeating: 0, count: 256)
        for pid in pids.prefix(max(count, 0)) where pid > 0 {
            if proc_name(pid, &buffer, UInt32(buffer.count)) > 0, String(cString: buffer) == name {
                return true
            }
        }
        return false
    }

    /// Bundle identifiers of the processes currently recording from any microphone.
    private static func appsUsingMicrophone() -> [String] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var processes = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr else { return [] }

        var bundles: [String] = []
        for process in processes {
            var running = UInt32(0)
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectGetPropertyData(process, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 else { continue }
            var bundle: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectGetPropertyData(process, &bundleAddress, 0, nil, &bundleSize, &bundle) == noErr, let bundle {
                bundles.append(bundle.takeRetainedValue() as String)
            }
        }
        return bundles
    }

    private static func microphoneInUse() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr else { return false }
        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    private static func cameraInUse() -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0 else { return false }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return false }
        for device in devices {
            var running: UInt32 = 0
            var runningAddress = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
            var dataUsed: UInt32 = 0
            if CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &dataUsed, &running) == 0, running != 0 {
                return true
            }
        }
        return false
    }
}

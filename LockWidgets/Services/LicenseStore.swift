import AppKit
import Security

/// Notchlight's licence. Everything works free for seven days; then a licence key bought through Polar unlocks it
/// on up to three Macs. Keys are checked with Polar's public licence API, so the app carries no secret. The key,
/// this Mac's activation and the trial's start live in the keychain, so reinstalling the app doesn't reset them.
final class LicenseStore: ObservableObject {
    static let shared = LicenseStore()

    static let checkoutURL = URL(string: "https://buy.polar.sh/polar_cl_3kwCipamOJFV6MggVZJUPtsrjRJcMMvz8Tsok1mVmVn")!
    /// Where buyers find their key again and free up a Mac.
    static let portalURL = URL(string: "https://polar.sh/notchlight/portal")!
    static let trialDays = 7
    private static let organizationID = "4fc1d092-2577-4313-aa82-7c3f10bffbdf"
    private static let api = URL(string: "https://api.polar.sh/v1/customer-portal/license-keys/")!
    /// How long a licence keeps working without reaching Polar, for a Mac that's offline.
    private static let offlineGrace: TimeInterval = 30 * 86400

    enum State: Equatable {
        case trial(daysLeft: Int)
        case expired
        case licensed
    }

    @Published private(set) var state: State = .trial(daysLeft: trialDays)
    @Published private(set) var isWorking = false
    /// What happened with the last activation or deactivation, for the Licence page.
    @Published private(set) var message: String?
    @Published private(set) var email: String?
    @Published private(set) var displayKey: String?

    /// True while Notchlight runs in full: during the trial or with a licence.
    var isActive: Bool { state != .expired }

    private var timer: Timer?

    private init() {
        #if DEBUG
        if WidgetGallery.isRendering { // Pictures for the website: no keychain, no network.
            state = .licensed
            return
        }
        #endif
        if Keychain.read(.trialStart) == nil {
            Keychain.write(.trialStart, ISO8601DateFormatter().string(from: .now))
        }
        email = UserDefaults.standard.string(forKey: "licenceEmail")
        displayKey = UserDefaults.standard.string(forKey: "licenceDisplayKey")
        updateState()
        validate()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.validate()
            self?.updateState()
        }
    }

    // MARK: State

    private var trialStart: Date {
        Keychain.read(.trialStart).flatMap { ISO8601DateFormatter().date(from: $0) } ?? .now
    }

    private var lastValidated: Date? {
        UserDefaults.standard.object(forKey: "licenceValidatedAt") as? Date
    }

    private func updateState() {
        let next: State
        if Keychain.read(.key) != nil, Keychain.read(.activation) != nil,
           let checked = lastValidated, Date.now.timeIntervalSince(checked) < Self.offlineGrace
        {
            next = .licensed
        } else {
            let calendar = Calendar.current
            let used = calendar.dateComponents([.day], from: calendar.startOfDay(for: trialStart), to: calendar.startOfDay(for: .now)).day ?? 0
            let left = Self.trialDays - used
            next = left > 0 ? .trial(daysLeft: left) : .expired
        }
        if state != next { state = next }
    }

    // MARK: Polar

    /// Activates a licence key on this Mac, named after the Mac so it's easy to recognise in Polar's portal.
    func activate(_ input: String) {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isWorking else { return }
        isWorking = true
        message = nil
        let label = Host.current().localizedName ?? "Mac"
        request("activate", ["key": key, "organization_id": Self.organizationID, "label": label]) { [weak self] status, json in
            guard let self else { return }
            isWorking = false
            switch status {
            case 200, 201:
                guard let activation = json?["id"] as? String else {
                    message = "Polar's reply didn't include an activation. Try again."
                    return
                }
                Keychain.write(.key, key)
                Keychain.write(.activation, activation)
                remember(json?["license_key"] as? [String: Any])
                message = "Notchlight is activated on this Mac. Thank you for buying it."
                updateState()
            case 403:
                message = "This key is already active on 3 Macs. Free one up in Polar's customer portal, then try again."
            case 404:
                message = "That key wasn't found. Check it against your receipt and try again."
            case 0:
                message = "Couldn't reach Polar. Check your internet connection and try again."
            default:
                message = "Polar couldn't activate the key (error \(status)). Try again in a moment."
            }
        }
    }

    /// Checks the licence with Polar. A key revoked, or this Mac freed up in the portal, stops counting; being
    /// offline doesn't, for up to 30 days.
    func validate() {
        guard let key = Keychain.read(.key), let activation = Keychain.read(.activation) else { return }
        request("validate", ["key": key, "organization_id": Self.organizationID, "activation_id": activation]) { [weak self] status, json in
            guard let self else { return }
            switch status {
            case 200 where json?["status"] as? String == "granted":
                remember(json)
            case 200, 404:
                forget()
                message = "This Mac's licence is no longer active."
            default:
                break
            }
            updateState()
        }
    }

    /// Frees this Mac's activation, so the key can be used on another Mac.
    func deactivate() {
        guard let key = Keychain.read(.key), let activation = Keychain.read(.activation), !isWorking else { return }
        isWorking = true
        request("deactivate", ["key": key, "organization_id": Self.organizationID, "activation_id": activation]) { [weak self] status, _ in
            guard let self else { return }
            isWorking = false
            if [200, 204, 404].contains(status) {
                forget()
                message = "This Mac is deactivated. Your key can now be used on another Mac."
                updateState()
            } else {
                message = "Couldn't reach Polar to deactivate this Mac. Try again when you're online."
            }
        }
    }

    private func remember(_ licence: [String: Any]?) {
        UserDefaults.standard.set(Date.now, forKey: "licenceValidatedAt")
        if let email = (licence?["customer"] as? [String: Any])?["email"] as? String {
            self.email = email
            UserDefaults.standard.set(email, forKey: "licenceEmail")
        }
        if let display = licence?["display_key"] as? String {
            displayKey = display
            UserDefaults.standard.set(display, forKey: "licenceDisplayKey")
        }
    }

    private func forget() {
        Keychain.delete(.key)
        Keychain.delete(.activation)
        for key in ["licenceValidatedAt", "licenceEmail", "licenceDisplayKey"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        email = nil
        displayKey = nil
    }

    private func request(_ endpoint: String, _ body: [String: String], done: @escaping (Int, [String: Any]?) -> Void) {
        var request = URLRequest(url: Self.api.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 20
        URLSession.shared.dataTask(with: request) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            DispatchQueue.main.async { done(status, json) }
        }
        .resume()
    }
}

/// The licence's few values in the login keychain, where they survive reinstalling the app.
private enum Keychain {
    enum Item: String {
        case trialStart, key, activation
    }

    private static let service = "com.victorabuchi.Notchlight.licence"

    private static func query(_ item: Item) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: item.rawValue]
    }

    static func read(_ item: Item) -> String? {
        var query = query(item)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ item: Item, _ value: String) {
        let data = Data(value.utf8)
        if SecItemUpdate(query(item) as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = query(item)
            add[kSecValueData as String] = data
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    static func delete(_ item: Item) {
        SecItemDelete(query(item) as CFDictionary)
    }
}

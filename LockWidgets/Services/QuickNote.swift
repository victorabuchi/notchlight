import AppKit

/// Light's note, kept in Apple Notes as a note called "Notchlight", so it's on the user's iPhone and other
/// Macs too. It's saved on this Mac as well, so it's there at once, and offline. Notes is asked only after
/// the first edit, so the permission prompt comes when the user is writing.
final class QuickNote: ObservableObject {
    static let shared = QuickNote()
    static let title = "Notchlight"

    @Published private(set) var text: String
    private let queue = DispatchQueue(label: "Notchlight.QuickNote")
    private var pending: DispatchWorkItem?
    /// The note's identifier in Notes, once it exists.
    private var noteID: String? {
        get { UserDefaults.standard.string(forKey: "lightNoteID") }
        set { UserDefaults.standard.set(newValue, forKey: "lightNoteID") }
    }

    private var syncs: Bool { SettingsKey.isOn(SettingsKey.lightNotesSync) }

    private init() {
        text = UserDefaults.standard.string(forKey: SettingsKey.lightNotes) ?? ""
    }

    /// The user typed: save here now, and in Notes after a pause.
    func edit(_ new: String) {
        guard new != text else { return }
        text = new
        UserDefaults.standard.set(new, forKey: SettingsKey.lightNotes)
        guard syncs else { return }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.push(new) }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    /// Reads the note back from Notes, for changes made on another device.
    func pull() {
        guard syncs, let id = noteID else { return }
        queue.async { [weak self] in
            var error: NSDictionary?
            guard let body = NSAppleScript(source: "tell application id \"com.apple.Notes\" to get plaintext of note id \"\(Self.escaped(id))\"")?
                .executeAndReturnError(&error).stringValue
            else {
                // The note was deleted in Notes: the next edit makes a new one.
                if (error?[NSAppleScript.errorNumber] as? Int) == -1728 { DispatchQueue.main.async { self?.noteID = nil } }
                return
            }
            let text = Self.withoutTitle(body)
            DispatchQueue.main.async {
                guard let self, self.pending == nil, text != self.text else { return }
                self.text = text
                UserDefaults.standard.set(text, forKey: SettingsKey.lightNotes)
            }
        }
    }

    /// The note in Notes, for the button on Light's note.
    func openInNotes() {
        guard let id = noteID else {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init())
            }
            return
        }
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: "tell application id \"com.apple.Notes\"\nactivate\nshow note id \"\(Self.escaped(id))\"\nend tell")?.executeAndReturnError(&error)
        }
    }

    private func push(_ text: String) {
        pending = nil
        let html = Self.html(text)
        let id = noteID
        queue.async { [weak self] in
            var error: NSDictionary?
            if let id {
                NSAppleScript(source: "tell application id \"com.apple.Notes\" to set body of note id \"\(Self.escaped(id))\" to \"\(Self.escaped(html))\"")?.executeAndReturnError(&error)
                if (error?[NSAppleScript.errorNumber] as? Int) != -1728 { return }
                // Deleted in Notes since: make it again below.
                error = nil
            }
            let made = NSAppleScript(source: "tell application id \"com.apple.Notes\" to get id of (make new note with properties {body:\"\(Self.escaped(html))\"})")?
                .executeAndReturnError(&error).stringValue
            if let made { DispatchQueue.main.async { self?.noteID = made } }
        }
    }

    /// The note's body: its title as the first line, then each line of the note.
    private static func html(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines).map { line in
            line.isEmpty ? "<div><br></div>" : "<div>\(line.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;"))</div>"
        }
        return "<div><b>\(title)</b></div>" + lines.joined()
    }

    private static func withoutTitle(_ body: String) -> String {
        var lines = body.components(separatedBy: .newlines)
        if lines.first?.trimmingCharacters(in: .whitespaces) == title { lines.removeFirst() }
        return lines.joined(separator: "\n")
    }

    private static func escaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

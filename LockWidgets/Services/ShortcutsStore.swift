import Foundation

/// The user's shortcuts from the Shortcuts app, to run from Light.
final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()

    @Published private(set) var names: [String] = []
    @Published private(set) var isLoaded = false

    func reload() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let names = Self.run(["list"])?
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty } ?? []
            DispatchQueue.main.async {
                self?.names = names
                self?.isLoaded = true
            }
        }
    }

    func run(_ name: String) {
        DispatchQueue.global(qos: .userInitiated).async { _ = Self.run(["run", name]) }
    }

    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}

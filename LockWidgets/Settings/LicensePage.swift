import SwiftUI

/// The trial, buying Notchlight, and entering or moving a licence key: where things stand, the key, and help
/// with the purchase.
struct LicensePage: View {
    var showsHeader = true
    @ObservedObject private var licence = LicenseStore.shared
    @State private var key = ""

    var body: some View {
        Form {
            if showsHeader {
                Section {
                    PageHeader(title: "Licence", subtitle: "Try everything free for 7 days, then buy Notchlight once to keep it on up to 3 Macs.")
                }
            }

            Section("Status") {
                HStack(spacing: 14) {
                    Image(systemName: status.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(status.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.title)
                            .font(.title2)
                        Text(status.detail)
                            .font(.headline)
                            .foregroundStyle(status.color)
                    }
                    Spacer()
                    if licence.state != .licensed {
                        Button("Buy Notchlight") { NSWorkspace.shared.open(LicenseStore.checkoutURL) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Access") {
                if licence.state == .licensed {
                    if let shown = licence.displayKey {
                        LabeledContent("Key") {
                            Text(shown).font(.body.monospaced())
                        }
                    }
                    Text("Each key works on up to 3 Macs. Deactivate this one to move your licence to another Mac.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Enter the licence key from your Notchlight receipt.")
                        .foregroundStyle(.secondary)
                    TextField("Licence key", text: $key, prompt: Text("NOTCHLIGHT-…"))
                        .font(.body.monospaced())
                        .onSubmit { licence.activate(key) }
                    HStack {
                        Button("Activate Licence") { licence.activate(key) }
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licence.isWorking)
                        if licence.isWorking { ProgressView().controlSize(.small) }
                    }
                }
                if let message = licence.message {
                    Text(message)
                }
            }

            Section("Your purchase") {
                Link("Find your key, or free up a Mac", destination: LicenseStore.portalURL)
                if licence.state == .licensed {
                    Button("Deactivate This Mac") { licence.deactivate() }
                        .buttonStyle(.link)
                        .disabled(licence.isWorking)
                }
                Link("Licence help", destination: URL(string: "https://notchlight.com/#faq-key")!)
                Link("Contact support", destination: URL(string: "mailto:support@notchlight.com")!)
                Button("Back to Welcome") { WelcomeController.shared.show() }
                    .buttonStyle(.link)
            }
        }
        .formStyle(.grouped)
    }

    private var status: (symbol: String, color: Color, title: String, detail: String) {
        switch licence.state {
        case let .trial(daysLeft):
            ("clock.fill", .blue, "Trial", daysLeft == 1 ? "1 day left" : "\(daysLeft) days left")
        case .expired:
            ("exclamationmark.circle.fill", .orange, "Trial ended", "Buy Notchlight to keep it")
        case .licensed:
            ("checkmark.seal.fill", .green, "Licensed", licence.email ?? "This Mac")
        }
    }
}

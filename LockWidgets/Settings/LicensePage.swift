import SwiftUI

/// The trial, buying Notchlight, and entering or moving a licence key.
struct LicensePage: View {
    @ObservedObject private var licence = LicenseStore.shared
    @State private var key = ""

    var body: some View {
        Form {
            Section {
                PageHeader(title: "Licence", subtitle: "Try everything free for 7 days, then buy Notchlight once to keep it on up to 3 Macs.")
            }

            Section {
                switch licence.state {
                case let .trial(daysLeft):
                    LabeledContent("Free trial") {
                        Text(daysLeft == 1 ? "1 day left" : "\(daysLeft) days left")
                    }
                case .expired:
                    LabeledContent("Free trial") {
                        Text("Ended").foregroundStyle(.red)
                    }
                case .licensed:
                    LabeledContent("Licensed to") {
                        Text(licence.email ?? "This Mac")
                    }
                    if let shown = licence.displayKey {
                        LabeledContent("Key") {
                            Text(shown).font(.body.monospaced())
                        }
                    }
                }
            } footer: {
                if licence.state == .expired {
                    Text("Your widgets and the Dynamic Island are paused until you add a licence key.")
                }
            }

            if licence.state == .licensed {
                Section {
                    HStack {
                        Button("Manage Your Macs…") { NSWorkspace.shared.open(LicenseStore.portalURL) }
                        Spacer()
                        Button("Deactivate This Mac") { licence.deactivate() }
                            .disabled(licence.isWorking)
                    }
                } footer: {
                    Text("Each key works on up to 3 Macs. Deactivate this one to move your licence to another Mac.")
                }
            } else {
                Section {
                    HStack {
                        Text("One payment, up to 3 Macs, no subscription.")
                        Spacer()
                        Button("Buy Notchlight…") { NSWorkspace.shared.open(LicenseStore.checkoutURL) }
                            .buttonStyle(.borderedProminent)
                    }
                }
                Section {
                    TextField("Licence key", text: $key, prompt: Text("NOTCHLIGHT-…"))
                        .font(.body.monospaced())
                        .onSubmit { licence.activate(key) }
                    HStack {
                        if licence.isWorking { ProgressView().controlSize(.small) }
                        Spacer()
                        Button("Activate") { licence.activate(key) }
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || licence.isWorking)
                    }
                } header: {
                    Text("Already bought it?")
                } footer: {
                    Text("Your key is on the page after checkout and in your receipt email.")
                }
            }

            if let message = licence.message {
                Section {
                    Text(message)
                }
            }
        }
        .formStyle(.grouped)
    }
}

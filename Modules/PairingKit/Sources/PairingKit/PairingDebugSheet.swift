//
//  PairingDebugSheet.swift
//  PairingKit
//
//  DEBUG BUILDS ONLY. What a developer needs and a user never sees: this
//  phone's code as text, a field to use a code by hand (the Simulator has
//  no camera), the attempt's state, and whatever the host adds (identity,
//  relay, the bench's knobs).
//

#if DEBUG
import SwiftUI
import UIKit

struct PairingDebugSheet<Content: View>: View {

    @ObservedObject var pairing: FaceToFacePairing
    let use: (String) -> Void
    @ViewBuilder let content: Content

    @Environment(\.dismiss) private var dismiss
    @State private var pasted = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Attempt") {
                    Text(describe(pairing.progress))
                }

                Section {
                    if let code = pairing.codeToShow {
                        Text(code)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                        Button("Copy") { UIPasteboard.general.string = code }
                    }
                } header: {
                    Text("This phone's code")
                } footer: {
                    Text("Changes once their code is read: it then says \"I have yours\".")
                }

                Section {
                    TextField("Paste their code", text: $pasted)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use") {
                        use(pasted.trimmingCharacters(in: .whitespacesAndNewlines))
                        pasted = ""
                    }
                    .disabled(pasted.isEmpty)
                } header: {
                    Text("Their code")
                } footer: {
                    Text("As if the camera had read it. Simulators share the Mac's clipboard.")
                }

                content
            }
            .navigationTitle("Pairing debug")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func describe(_ progress: FaceToFacePairing.Progress) -> String {
        switch progress {
        case .looking: return "Looking"
        case .readTheirs(let contact): return "Read \(contact.displayName); waiting for their confirmation"
        case .bothWays(let contact): return "Paired both ways with \(contact.displayName)"
        case .refused(let error): return "Refused: \(error)"
        }
    }
}
#endif

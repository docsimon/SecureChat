//
//  PairingView.swift
//  SecureChat
//
//  "Add contact": hold the two phones face to face.
//

import SwiftUI
import PairingKit

struct PairingView: View {

    @Bindable var viewModel: PairingViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.phase {
                case .needsName:
                    nameStep
                case .pairing(let pairing):
                    // PairingKit's screens, shared with the harnesses.
                    FaceToFacePairingView(pairing: pairing,
                                          scan: { viewModel.scanned($0) },
                                          onScannerFailure: { viewModel.scannerFailed($0) }) {
#if DEBUG
                        Section("SecureChat") {
                            LabeledContent("Account", value: viewModel.debugAccount)
                        }
#endif
                    }
                case .unavailable(let message):
                    ContentUnavailableView("Can't add a contact", systemImage: "exclamationmark.triangle",
                                           description: Text(message))
                }
            }
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var nameStep: some View {
        Form {
            Section {
                TextField("Your name", text: $viewModel.draftName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .submitLabel(.continue)
                    .onSubmit { viewModel.confirmName() }
            } footer: {
                Text("Shown to the people you pair with. They can change what they call you on their own phone.")
            }
            Button("Continue") { viewModel.confirmName() }
                .disabled(!viewModel.canConfirmName)
        }
    }
}

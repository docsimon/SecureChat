//
//  FaceToFacePairingSheet.swift
//  SessionTestApp
//
//  Pairing with the phones held screen to screen, so this harness can
//  become a contact of SecureChat on another phone (SecureChat pairs no
//  other way). The screens are PairingKit's `FaceToFacePairingView`, the
//  ones SecureChat shows; this only adds the harness's identity, log, and
//  its lines in the debug sheet.
//

import SwiftUI
import PairingKit

struct FaceToFacePairingSheet: View {

    @ObservedObject private var model: SessionHarnessModel
    @StateObject private var pairing: FaceToFacePairing
    @Environment(\.dismiss) private var dismiss

    init(model: SessionHarnessModel) {
        self.model = model
        _pairing = StateObject(wrappedValue: FaceToFacePairing(
            identityPublicKey: model.identity.publicKey.rawRepresentation,
            accountUUID: model.accountUUID,
            displayName: model.displayName,
            contacts: { model.contacts },
            store: { model.add($0) }))
    }

    var body: some View {
        NavigationStack {
            FaceToFacePairingView(
                pairing: pairing,
                scan: { [pairing, model] code in
                    let event = pairing.scanned(code)
                    if case .refused(let error) = event {
                        model.record("Pairing code refused: \(error)", isError: true)
                    }
                    return event
                },
                onScannerFailure: { model.scannerFailed($0) }) {
                Section("Session harness") {
                    LabeledContent("Account", value: model.accountUUID.uuidString)
                    LabeledContent("Relay", value: model.relayURL)
                    LabeledContent("Contacts", value: "\(model.contacts.count)")
                }
            }
            .navigationTitle("Pair face to face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

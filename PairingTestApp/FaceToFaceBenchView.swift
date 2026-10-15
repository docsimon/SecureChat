//
//  FaceToFaceBenchView.swift
//  PairingTestApp
//
//  Test bench for pairing with the phones held face to face. The screens
//  are PairingKit's `FaceToFacePairingView`, exactly as SecureChat shows
//  them; the bench puts its knob (error correction) in the debug sheet and
//  times each attempt into the harness log.
//

import SwiftUI
import PairingKit

struct FaceToFaceBenchView: View {

    @ObservedObject private var model: PairingHarnessModel
    @StateObject private var pairing: FaceToFacePairing

    @Environment(\.dismiss) private var dismiss
    @State private var lowCorrection = false
    @State private var camera: QRCodeScannerView.Camera = .front
    @State private var openedAt = Date()
    /// When this attempt first read the other code.
    @State private var readAt: Date?

    init(model: PairingHarnessModel) {
        self.model = model
        _pairing = StateObject(wrappedValue: FaceToFacePairing(
            identityPublicKey: model.identityPublicKey,
            accountUUID: model.accountUUID,
            displayName: model.displayName,
            contacts: { model.contacts },
            store: { model.add($0) }))
    }

    var body: some View {
        NavigationStack {
            FaceToFacePairingView(
                pairing: pairing,
                errorCorrection: lowCorrection ? .low : .medium,
                scan: { code in
                    let event = pairing.scanned(code)
                    if let event { record(event) }
                    return event
                },
                onCameraChange: { camera in self.camera = camera },
                onScannerFailure: { model.scannerFailed($0) }) {
                Section("Bench") {
                    Toggle("Bigger squares (less error correction)", isOn: $lowCorrection)
                }
            }
            .navigationTitle("Face to face")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear(perform: restartClock)
        .onReceive(pairing.$progress) { progress in
            switch progress {
            case .looking:
                restartClock()   // a new attempt: Pair tapped, or the camera switched
            case .timedOut(let contact):
                model.note("Timed out waiting for \(contact.displayName) to confirm")
            case .readTheirs, .bothWays, .refused:
                break
            }
        }
    }

    private func record(_ event: FaceToFacePairing.Event) {
        // The only clock that starts at a known moment is tapping Pair,
        // so the first figure includes however long it took to get the two
        // phones in front of each other. The second is the one that says
        // something about reading: the gap between the two reads.
        let now = Date()
        let sinceOpened = String(format: "%.1f s after Pair was tapped", now.timeIntervalSince(openedAt))
        let settings = "\(camera == .front ? "front" : "rear") camera, \(lowCorrection ? "low" : "medium") error correction on this screen"
        switch event {
        case .readTheirs:
            readAt = now
            model.note("Read their code \(sinceOpened) (\(settings))")
        case .completed:
            if let readAt {
                model.note(String(format: "Paired both ways %.1f s after reading their code", now.timeIntervalSince(readAt)))
            } else {
                model.note("Paired both ways on the first read, \(sinceOpened) (\(settings))")
            }
        case .refused(let error):
            model.noteRefusal(error)
        }
    }

    private func restartClock() {
        openedAt = Date()
        readAt = nil
    }
}

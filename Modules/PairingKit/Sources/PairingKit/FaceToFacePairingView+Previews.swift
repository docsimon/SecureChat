//
//  FaceToFacePairingView+Previews.swift
//  PairingKit
//
//  The pairing screens in every state they can show, for iterating on how
//  they look without two phones. Open this file in Xcode with the canvas on
//  (⌥⌘↩) and pick a device in the canvas to see another size. The phones
//  remain the judge of what a preview cannot show: reading distance,
//  glare, and whether the vibration is felt.
//
//  The camera window is a still here: previews have no camera.
//

#if DEBUG
import SwiftUI
import CryptoKit

/// A pairing attempt as previews need one.
@MainActor
enum PairingPreviewState {

    private static let ownKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

    static func looking() -> FaceToFacePairing {
        FaceToFacePairing(identityPublicKey: ownKey, accountUUID: UUID(), displayName: "Ada",
                          contacts: { [] }, store: { _ in })
    }

    /// Their code read: our code now carries the acknowledgement.
    static func readTheirs(name: String = "Grace") -> FaceToFacePairing {
        let pairing = looking()
        _ = pairing.scanned(code(name: name))
        return pairing
    }

    private static func code(name: String) -> String {
        (try? PairingPayload(identityPublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
                             accountUUID: UUID(), displayName: name, acknowledging: nil).encoded()) ?? ""
    }
}

/// As SecureChat presents it: in a navigation stack, with a Close button.
private struct PreviewHost<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Add contact")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") {} }
                }
        }
    }
}

@MainActor
private func pairingScreen(_ screen: FaceToFacePairingView<EmptyView>.Screen,
                           pairing: FaceToFacePairing = PairingPreviewState.looking(),
                           outcome: PairingOutcome? = nil,
                           problem: QRCodeScannerView.Failure? = nil) -> some View {
    PreviewHost {
        FaceToFacePairingView(pairing: pairing, signal: { _ in }, screen: screen, outcome: outcome,
                              cameraFeed: .still, scannerProblem: problem) { EmptyView() }
    }
}

// MARK: Start screen

#Preview("Start") {
    pairingScreen(.start)
}

#Preview("Start · paired") {
    pairingScreen(.start, outcome: .paired("Grace"))
}

#Preview("Start · timed out, long name") {
    pairingScreen(.start, outcome: .timedOut("Maximilian Alexander Ferdinand von Habsburg-Lothringen"))
}

#Preview("Start · nothing read") {
    pairingScreen(.start, outcome: .nothingRead)
}

#Preview("Start · refused") {
    pairingScreen(.start, outcome: .refused(.notAPairingCode))
}

#Preview("Start · camera denied") {
    pairingScreen(.start, problem: .accessDenied)
}

#Preview("Start · largest text") {
    pairingScreen(.start, outcome: .timedOut("Grace"))
        .dynamicTypeSize(.accessibility5)
}

#Preview("Start · dark") {
    pairingScreen(.start, outcome: .paired("Grace"))
        .preferredColorScheme(.dark)
}

// MARK: Code screen

#Preview("Code") {
    pairingScreen(.code)
}

#Preview("Code · their code read") {
    pairingScreen(.code, pairing: PairingPreviewState.readTheirs())
}

#Preview("Code · camera denied") {
    pairingScreen(.code, problem: .accessDenied)
}

#Preview("Code · no camera") {
    pairingScreen(.code, problem: .cameraUnavailable)
}

#Preview("Code · largest text, dark") {
    pairingScreen(.code)
        .dynamicTypeSize(.accessibility5)
        .preferredColorScheme(.dark)
}
#endif

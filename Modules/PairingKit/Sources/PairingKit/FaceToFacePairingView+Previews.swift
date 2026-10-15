//
//  FaceToFacePairingView+Previews.swift
//  PairingKit
//
//  The pairing screen in every state it can show, for iterating on how it
//  looks without two phones. Open this file in Xcode with the canvas on
//  (⌥⌘↩) and pick a device in the canvas to see another size (the iPhone
//  SE is the smallest supported screen). The phones remain the judge of
//  what a preview cannot show: reading distance, glare, and whether the
//  vibration is felt. There is no camera here.
//

#if DEBUG
import SwiftUI
import CryptoKit

/// Pairing attempts put into a given state the way a real one gets there:
/// by reading codes.
@MainActor
enum PairingPreviewState {

    private static let ownKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation

    static func looking() -> FaceToFacePairing {
        FaceToFacePairing(identityPublicKey: ownKey, accountUUID: UUID(), displayName: "Ada",
                          contacts: { [] }, store: { _ in })
    }

    /// Their code read; they have not read ours yet.
    static func readTheirs(name: String = "Grace") -> FaceToFacePairing {
        let pairing = looking()
        _ = pairing.scanned(code(name: name, acknowledgingUs: false))
        return pairing
    }

    static func bothWays(name: String = "Grace") -> FaceToFacePairing {
        let pairing = looking()
        _ = pairing.scanned(code(name: name, acknowledgingUs: true))
        return pairing
    }

    static func refused() -> FaceToFacePairing {
        let pairing = looking()
        _ = pairing.scanned("https://example.com/menu")
        return pairing
    }

    private static func code(name: String, acknowledgingUs: Bool) -> String {
        (try? PairingPayload(identityPublicKey: Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation,
                             accountUUID: UUID(), displayName: name,
                             acknowledging: acknowledgingUs ? ownKey : nil).encoded()) ?? ""
    }
}

/// As SecureChat presents it: in a navigation stack, with a Close button.
@MainActor
private func pairingScreen(_ pairing: FaceToFacePairing,
                           problem: QRCodeScannerView.Failure? = nil) -> some View {
    NavigationStack {
        FaceToFacePairingView(pairing: pairing, signal: { _ in }, cameraFeed: .none,
                              scannerProblem: problem) { EmptyView() }
            .navigationTitle("Add contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") {} }
            }
    }
}

#Preview("Looking") {
    pairingScreen(PairingPreviewState.looking())
}

#Preview("Got them") {
    pairingScreen(PairingPreviewState.readTheirs())
}

#Preview("Paired") {
    pairingScreen(PairingPreviewState.bothWays())
}

#Preview("Refused") {
    pairingScreen(PairingPreviewState.refused())
}

#Preview("Camera denied") {
    pairingScreen(PairingPreviewState.looking(), problem: .accessDenied)
}

#Preview("No camera") {
    pairingScreen(PairingPreviewState.looking(), problem: .cameraUnavailable)
}

#Preview("Long name") {
    pairingScreen(PairingPreviewState.readTheirs(name: "Maximilian Alexander Ferdinand von Habsburg-Lothringen"))
}

#Preview("Largest text") {
    pairingScreen(PairingPreviewState.readTheirs())
        .dynamicTypeSize(.accessibility5)
}

#Preview("Dark mode around it") {
    pairingScreen(PairingPreviewState.bothWays())
        .preferredColorScheme(.dark)
}
#endif

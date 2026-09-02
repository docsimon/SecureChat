import Foundation
import CryptoKit
import Observation
import AppAttestKit

/// APP-OWNED. This is the piece that would be reused if a second app ever
/// existed — it is the flow's state machine, separate from the SwiftUI views
/// which carry copy, branding, and design system and never survive a move.
/// See module doc §2.
@Observable
@MainActor
final class RegistrationViewModel {

    enum Screen {
        case welcome            // "No account needed" — sells the absence
        case working            // silent attestation, ~300ms
        case identity           // "This is you" — makes setup legible
        case deferred(String)   // no network: let them in, retry later
        case unsupported(String)
    }

    private(set) var screen: Screen = .welcome
    private(set) var fingerprint: String = ""
    var displayName: String = ""

    private let coordinator: AttestationCoordinator
    private let identityKey: Curve25519.KeyAgreement.PrivateKey

    init(baseURL: URL) throws {
        // STEP 1 — identity keypair FIRST. App-owned.
        let key = try IdentityKeyStore.loadOrCreate()
        self.identityKey = key
        self.fingerprint = Self.fingerprint(for: key.publicKey.rawRepresentation)

        let publicKey = key.publicKey.rawRepresentation
        let transport = AuthTransport(
            baseURL: baseURL,
            identityPublicKey: publicKey,
            onAccountCreated: { uuid in
                // App owns the account model, not the module.
                UserDefaults.standard.set(uuid, forKey: "account-uuid")
            })

        // Note what the app CAN'T inject: no service, no keystore. Those seams
        // are internal to the package, so the app cannot reach around the
        // coordinator to call attestKey or write a keyId itself.
        self.coordinator = AttestationCoordinator(
            transport: transport,
            observer: AttestationLogger())
    }

    /// Safe to call from launch, foreground, and connectivity change — the
    /// coordinator deduplicates overlapping calls internally.
    func start() async {
        screen = .working
        await coordinator.restore()

        do {
            // STEP 6 lives HERE, in the app. This binding is the step that makes
            // the whole scheme work: the App Attest key signs over a hash
            // CONTAINING the identity public key, so the server can conclude that
            // this identity key was presented by a genuine app on real hardware.
            // Without it, anyone could attach any identity key to a valid
            // attestation.
            //
            // The module supplies the challenge and receives an opaque hash. It
            // never learns that identity keys exist.
            let publicKey = identityKey.publicKey.rawRepresentation
            let state = try await coordinator.ensureAttested { challenge in
                Data(SHA256.hash(data: challenge + publicKey))
            }

            switch state {
            case .attested:
                screen = .identity
            case .unsupported:
                screen = .unsupported("This device can't be verified.")
            default:
                screen = .deferred("Setup incomplete. Retrying…")
            }
        } catch let error as AttestationError {
            switch error {
            case .networkUnavailable, .exhausted:
                // Do NOT block behind a spinner. Let the user in, mark
                // unregistered, retry on foreground and connectivity change.
                // They cannot pair until this succeeds — surface that on the
                // "add contact" screen, not here. See architecture doc §8.
                screen = .deferred("You're offline. We'll finish setup later.")
            case .unsupported:
                screen = .unsupported("This device can't be verified.")
            default:
                screen = .deferred("Setup didn't complete. We'll retry.")
            }
        } catch {
            screen = .deferred("Setup didn't complete. We'll retry.")
        }
    }

    /// Hand the coordinator to the session layer for assertion signing.
    /// Note the type: `AssertionSigning`, not the concrete coordinator — the
    /// session layer only needs to sign, not to drive registration.
    var signer: AssertionSigning { coordinator }

    /// Derived deterministically from the identity public key. Gives the user
    /// something concrete that resulted from a silent setup, and it is the same
    /// artifact used later for pairing verification. Never user-editable.
    private static func fingerprint(for publicKey: Data) -> String {
        let words = ["otter", "canyon", "amber", "willow", "cobalt", "ferry",
                     "lantern", "marble", "nectar", "pilot", "quartz", "raven"]
        let digest = Array(SHA256.hash(data: publicKey))
        let a = words[Int(digest[0]) % words.count]
        let b = words[Int(digest[1]) % words.count]
        let n = (Int(digest[2]) << 8 | Int(digest[3])) % 10000
        return "\(a)-\(b)-\(String(format: "%04d", n))"
    }
}

/// Diagnostics only — NOT a UI driver. It fires from actor context, so driving
/// @Observable state from here would need an explicit MainActor hop. The view
/// model reads coordinator state instead. See module doc §3.
struct AttestationLogger: AttestationObserver {
    func didTransition(to state: AttestationState) {
        // `label`, never the keyId — that is a persistent device identifier and
        // must not reach a crash reporter. See architecture doc §10.
        print("[attest] -> \(state.label)")
    }
    func didFail(_ error: AttestationError, attempt: Int) {
        print("[attest] failed (attempt \(attempt)): \(error.diagnosticName)")
    }
}

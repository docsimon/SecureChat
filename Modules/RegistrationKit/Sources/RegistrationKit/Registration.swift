//
//  Registration.swift
//  RegistrationKit
//
//  The two pieces of registration policy every caller must get identically
//  right, kept in one place so the app and the harness cannot drift apart.
//

import Foundation
import CryptoKit
import AppAttestKit

public enum Registration {

    /// The `binding` to pass to `AttestationCoordinator.ensureAttested`.
    ///
    /// `SHA256(challenge)` alone, NOT `SHA256(challenge ‖ identityPublicKey)`:
    /// the server's verification library fixes this formula, so the identity
    /// binding lives server-side (the challenge is issued bound to an
    /// identity public key and checked back at /register — see
    /// `RealAttestationTransport`).
    public static let clientDataHash: @Sendable (Data) throws -> Data = { challenge in
        Data(SHA256.hash(data: challenge))
    }

    /// Clears whatever a PREVIOUS install left in the Keychain: identity key,
    /// App Attest state, stored account id. Run it through
    /// `FirstLaunchPurgeGate`, never unconditionally — on anything but the
    /// first launch after an install it would throw away a live registration.
    ///
    /// The Keychain survives deleting the app; the App Attest key it points
    /// to does not. Left alone, a reinstalled app would read back "attested"
    /// for a key Apple no longer recognises.
    ///
    /// - Returns: whether anything was there to clear.
    @discardableResult
    public static func purgeStaleInstallState(coordinator: AttestationCoordinator,
                                              identity: IdentityKeyStore = .live,
                                              account: RegisteredAccountStore = .live) async -> Bool {
        let hadIdentity = identity.exists()
        if hadIdentity {
            identity.delete()
        }
        // Unreadable counts as "something is there": a purge that skipped on
        // a failed read would leave the stale key behind for good, since the
        // gate runs once per install.
        let readable = (try? await coordinator.restore()) != nil
        let hadModuleState = await coordinator.currentState != .none || !readable
        // Only when there is something to clear: on a genuinely new install
        // this must not touch the module at all.
        if hadModuleState {
            await coordinator.acknowledgeKeyInvalidation()
        }
        guard hadIdentity || hadModuleState else { return false }
        // Stale from whatever registration that Keychain state belonged to —
        // the NEXT registration will be given a different account id.
        account.current = nil
        return true
    }
}

//
//  AttestationKeyStore.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation

// Seam over persistence. The module owns `keyId` storage because it owns the
// "retry with the same keyId" rule — if the app held it, that rule would not
// be enforceable. Also caches the attestation object (see AttestationState).
protocol AttestationKeyStore: Sendable {
    func loadKeyId() throws -> String?
    func store(keyId: String) throws
    /// Records that the SERVER confirmed registration. Without this, a relaunch
    /// cannot distinguish "key generated, never attested" from "fully registered",
    /// and would try to re-attest a one-shot key — burning a key regeneration and
    /// eventually locking the user out.
    func loadIsAttested() throws -> Bool
    func store(isAttested: Bool) throws
    func loadAttestation() throws -> (object: Data, challenge: Data)?
    func store(attestation: Data, challenge: Data) throws
    func clearAttestation() throws
    /// Persisted across launches so a bug cannot loop and burn the device's
    /// lifetime key budget.
    func loadRegenerationCount() throws -> Int
    func store(regenerationCount: Int) throws
    func clear() throws
}

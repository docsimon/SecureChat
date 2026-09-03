//
//  AttestationState.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation

import Foundation

/// Where the one-time attestation flow currently stands.
///
/// CRITICAL: every case must be reconstructible from persisted data alone,
/// because the app can be killed at any point in the flow. See module doc §5.
public enum AttestationState: Sendable, Equatable {

    /// Nothing persisted yet.
    case none

    /// An App Attest key exists and its `keyId` is persisted.
    /// Persisted BEFORE calling `attestKey` — a crash here must not orphan the key,
    /// because key generations are capped per device for the device's lifetime.
    case keyGenerated(keyId: String)

    /// `attestKey` returned but the server has not confirmed registration.
    ///
    /// This state exists because App Attest keys can only be attested ONCE.
    /// If we lost the attestation blob after a successful `attestKey`, a retry
    /// would fail with `invalidKey` and we could not tell "never attested" from
    /// "attested, receipt lost". Caching it makes the upload independently
    /// retryable. See module doc §7a.
    case attestationPending(keyId: String, attestation: Data, challenge: Data)

    /// Server confirmed. Assertions are now possible.
    case attested(keyId: String)

    /// Terminal. Simulator, jailbroken device, or some enterprise configs.
    case unsupported(AttestationError)

    /// Safe for logging — deliberately omits `keyId`, which is a persistent
    /// device identifier and must not reach a crash reporter.
    /// See architecture doc §10.
    public var label: String {
        switch self {
        case .none:               return "none"
        case .keyGenerated:       return "keyGenerated"
        case .attestationPending: return "attestationPending"
        case .attested:           return "attested"
        case .unsupported:        return "unsupported"
        }
    }

    public var isAttested: Bool {
        if case .attested = self { return true }
        return false
    }
}

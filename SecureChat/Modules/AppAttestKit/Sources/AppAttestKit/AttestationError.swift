//
//  AttestationError.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation
import DeviceCheck

/// Deliberately COARSE. An earlier design had four discriminated cases including
/// `transient(retryAfter:)` and `keyRateLimited`; both were wrong:
///
///   - Apple provides no `retryAfter` value, so that case could never be populated.
///   - Rate limiting is likely indistinguishable from a transient failure — it
///     plausibly arrives as `serverUnavailable` or `unknownSystemFailure`.
///
/// A fine-grained taxonomy invited exactly the mistake it was meant to prevent.
/// The coarse rule below is correct regardless of which code Apple returns.
/// See module doc §6.
public enum AttestationError: Error, Sendable, Equatable {

    /// Simulator, jailbroken, or unsupported configuration. Terminal.
    case unsupported

    /// The key is dead — Keychain cleared, device restored from backup.
    /// THE ONLY error on which regenerating a key is correct.
    case keyInvalid

    /// Anything else from Apple. Retry the SAME keyId with backoff.
    case retryable(String)

    /// No connectivity. Defer; retry on foreground / connectivity change.
    case networkUnavailable

    /// Our server rejected the attestation. Terminal — a retry will not help.
    case serverRejected(String)

    /// Cached attestation outlived its challenge. The one bounded case where
    /// regenerating a key is correct — capped, see `Policy.maxKeyRegenerations`.
    case challengeExpired

    /// Retry budget exhausted.
    case exhausted

    /// Assertion attempted before registration completed.
    case notAttested

    /// THE CARDINAL RULE. Calling `generateKey()` on any other error will
    /// eventually exhaust the device's lifetime key budget and lock the user
    /// out permanently, with no recovery path.
    var requiresNewKey: Bool {
        switch self {
        case .keyInvalid, .challengeExpired: return true
        default: return false
        }
    }

    var isRetryable: Bool {
        switch self {
        case .retryable, .networkUnavailable: return true
        default: return false
        }
    }

    /// Safe for logs — no keyId, no attestation bytes.
    public var diagnosticName: String {
        switch self {
        case .unsupported:        return "unsupported"
        case .keyInvalid:         return "keyInvalid"
        case .retryable:          return "retryable"
        case .networkUnavailable: return "networkUnavailable"
        case .serverRejected:     return "serverRejected"
        case .challengeExpired:   return "challengeExpired"
        case .exhausted:          return "exhausted"
        case .notAttested:        return "notAttested"
        }
    }
}

extension AttestationError {
    /// ⚠️ VERIFY THIS MAPPING AGAINST CURRENT APPLE DOCUMENTATION BEFORE SHIPPING.
    /// The `DCError` code list this was written against is from mid-2025 and may
    /// be incomplete or renamed. This is the one place where being wrong strands
    /// users permanently. See module doc §6.
    static func from(_ error: Error) -> AttestationError {
        if let already = error as? AttestationError { return already }

        let ns = error as NSError
        guard ns.domain == DCError.errorDomain,
              let code = DCError.Code(rawValue: ns.code) else {
            return .retryable(ns.domain)
        }

        switch code {
        case .featureUnsupported:
            return .unsupported
        case .invalidKey:
            return .keyInvalid
        case .invalidInput:
            // A bug on our side — a malformed hash, not something a retry fixes.
            return .serverRejected("invalidInput")
        case .serverUnavailable, .unknownSystemFailure:
            // Note: rate limiting probably lands here too. We deliberately do
            // NOT try to distinguish it, because guessing wrong and regenerating
            // a key is far more damaging than an extra backoff cycle.
            return .retryable(String(describing: code))
        @unknown default:
            return .retryable("unknown")
        }
    }
}

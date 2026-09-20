//
//  HarnessEvent.swift
//  AppAttestTestApp
//
//  Shared history model — used by both the mock UX preview and, once
//  approved, the real flow. Not mock-specific: this is the reusable part.
//

import Foundation

struct DetailField: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let value: String
}

struct HarnessEvent: Identifiable {
    enum Kind: String {
        // Each label is tagged with WHERE it actually happens, since that's
        // exactly what's easy to lose track of otherwise: generateKey() and
        // generateAssertion() are both purely local (Secure Enclave only,
        // no network at all — confirmed for generateAssertion via web search
        // this session); attestKey() is the ONLY call that produces a real
        // response from Apple's own servers (the CBOR attestation object);
        // the challenge fetch and registration submission hit YOUR Auth
        // Server (architecture-decisions.md §6), a third, separate party.
        case identityKeyGenerated = "Identity Key Generated (local)"
        case attestationStarted = "Attestation Started"
        case attestationStepChallenge = "Challenge Fetched (Auth Server)"
        case attestationStepKeyGenerated = "App Attest Key Generated (local)"
        case attestationStepAttested = "Attestation Received (Apple)"
        case attestationStepSubmitted = "Submitted (Auth Server)"
        case attestationFailed = "Attestation Failed"
        case assertionSigned = "Assertion Signed (local)"
        case moduleReset = "Module State Reset"
        case identityKeyDeleted = "Identity Key Deleted"

        var systemImage: String {
            switch self {
            case .identityKeyGenerated: return "person.badge.key"
            case .attestationStarted: return "play.circle"
            case .attestationStepChallenge: return "number"
            case .attestationStepKeyGenerated: return "key"
            case .attestationStepAttested: return "checkmark.seal"
            case .attestationStepSubmitted: return "arrow.up.doc"
            case .attestationFailed: return "exclamationmark.triangle"
            case .assertionSigned: return "signature"
            case .moduleReset: return "arrow.counterclockwise"
            case .identityKeyDeleted: return "trash"
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let timestamp: Date
    let summary: String
    var detail: [DetailField] = []
    var isError: Bool = false
}

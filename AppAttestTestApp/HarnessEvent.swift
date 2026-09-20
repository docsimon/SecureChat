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
        case identityKeyGenerated = "Identity Key Generated"
        case attestationStarted = "Attestation Started"
        case attestationStepChallenge = "Challenge Fetched"
        case attestationStepKeyGenerated = "App Attest Key Generated"
        case attestationStepAttested = "Attested with Apple"
        case attestationStepSubmitted = "Submitted to Server"
        case attestationFailed = "Attestation Failed"
        case assertionSigned = "Assertion Signed"
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

//
//  AttestationSubmission.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 02/09/2026.
//

import Foundation

/// What the app POSTs to `/register`. Every field is a PUBLIC credential —
/// private keys never leave the device — so TLS in transit is sufficient and no
/// application-layer encryption is needed. See module doc §2a.
public struct AttestationSubmission: Sendable {
    public let keyId: String
    public let challenge: Data
    public let attestation: Data

    public init(keyId: String, challenge: Data, attestation: Data) {
        self.keyId = keyId
        self.challenge = challenge
        self.attestation = attestation
    }

    // NOTE: the identity public key is NOT here. The app already holds it and
    // adds it when serialising this to its own wire format — the module has no
    // reason to carry app protocol data through its own types.
}

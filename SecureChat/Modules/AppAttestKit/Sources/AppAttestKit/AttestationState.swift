//
//  AttestationState.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 30/08/2026.
//

import Foundation

public enum AttestationState: Sendable {
    case none
    case keyGenerated(keyId: String)
    case attestationPending(keyId: String, attestation: Data, challenge: Data)  // new
    case attested(keyId: String)
    case unsupported(AttestationError)
}

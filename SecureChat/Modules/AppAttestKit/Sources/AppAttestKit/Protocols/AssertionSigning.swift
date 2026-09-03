//
//  AssertionSigning.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 02/09/2026.
//

import Foundation

/// Assertions are deliberately NOT routed through `AttestationTransport`:
/// attestation DRIVES a network call, whereas an assertion is DRIVEN BY a
/// network call the app already makes. Merging them would drag the entire
/// session layer through an interface designed for a one-time flow.
///
/// Module PERFORMS, app DRIVES: signing needs the keyId (which the app never
/// sees), but *when* and *what* to sign is entirely the app's decision.
public protocol AssertionSigning: Sendable {
    func sign(_ payload: Data) async throws -> Data
}

//
//  AttestationTransport.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 02/09/2026.
//

import Foundation

/// The module never knows a URL. The app implements this against its endpoints.
///
/// Scoped to the ONE-TIME registration flow only. Assertions do NOT go through
/// here — they have a different lifetime and inverted control flow. See `AssertionSigning`.
public protocol AttestationTransport: Sendable {
    func fetchChallenge() async throws -> Data
    func submitAttestation(_ request: AttestationSubmission) async throws -> String
}

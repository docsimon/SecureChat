//
//  LocalFakeTransport.swift
//  AppAttestTestApp
//
//  APP-OWNED. Implements `AttestationTransport` with no network at all.
//
//  Nothing this harness needs to prove — isSupported, generateKey, attestKey,
//  generateAssertion, and whether AttestationCoordinator's state machine
//  drives correctly through real Apple responses — requires a real server.
//  A real /challenge + /register backend is separate, later work (it needs
//  its own attestation verifier — see architecture-decisions.md §2's
//  verification steps). This fake stands in until that exists: it only has
//  to be *consistent* (same shape as the real protocol), not correct in any
//  security sense.
//
//  See pairing-workflow.md and account-keys-reference.md for why none of
//  this is a stand-in for real server verification — it deliberately isn't.
//

import Foundation
import AppAttestKit

/// Every call is logged through `onEvent` so the harness UI can show exactly
/// what the module attempted to send, without needing a real endpoint to
/// receive it.
struct LocalFakeTransport: AttestationTransport {
    let onEvent: @Sendable (String) -> Void

    func fetchChallenge() async throws -> Data {
        let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        onEvent("fake /challenge → \(challenge.count) random bytes")
        return challenge
    }

    func submitAttestation(_ request: AttestationSubmission) async throws -> String {
        let fakeAccountUUID = UUID().uuidString
        onEvent("environment: \(AttestationEnvironmentHint.describe(request.attestation))")
        onEvent("fake /register ← keyId hash \(request.keyId.prefix(8))…, "
                + "attestation \(request.attestation.count) bytes")
        onEvent("fake /register → account \(fakeAccountUUID)")
        return fakeAccountUUID
    }
}

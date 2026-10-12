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
import RegistrationKit

struct LocalFakeTransport: AttestationTransport {
    let onEvent: @Sendable (TransportEvent) -> Void

    func fetchChallenge() async throws -> Data {
        let challenge = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        onEvent(.challengeFetched(byteCount: challenge.count))
        return challenge
    }

    func submitAttestation(_ request: AttestationSubmission) async throws -> String {
        let fakeAccountUUID = UUID().uuidString
        onEvent(.submitted(accountUUID: fakeAccountUUID))
        return fakeAccountUUID
    }
}

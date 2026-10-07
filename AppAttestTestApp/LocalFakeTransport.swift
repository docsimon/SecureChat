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

/// Deliberately does NOT expose `AttestationSubmission.keyId` through this
/// event type at all — not even truncated. Once this transport is driven by
/// real data, `keyId` is a real, persistent App Attest key identifier, and
/// architecture doc §10 is explicit that it must never reach a log. Making
/// that structurally impossible (rather than "remember not to log it") is
/// the point of this enum, not a style choice.
enum TransportEvent: Sendable {
    case challengeFetched(byteCount: Int)
    case submitted(accountUUID: String)
    /// Session token deliberately NOT included, even truncated — it's a live
    /// credential, same reasoning as never logging keyId.
    case sessionOpened(tokenByteCount: Int)
    /// `statusCode == nil` means the request never got an HTTP response at
    /// all (URLSession itself threw — no connection, DNS failure, Local
    /// Network permission denied). A real status code means the server WAS
    /// reached and responded with a rejection — a completely different
    /// failure class from "couldn't reach it." See `AuthServerRequest.swift`'s
    /// `performAuthServerRequest` for why this distinction matters.
    case requestFailed(endpoint: String, statusCode: Int?, detail: String)
    /// Step control (`ControllableTransport`) is holding the flow at this
    /// point / has let it go on.
    case paused(at: String)
    case resumed(at: String)
}

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

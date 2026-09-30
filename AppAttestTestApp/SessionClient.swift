//
//  SessionClient.swift
//  AppAttestTestApp
//
//  APP-OWNED. Demonstrates the assertion flow — the OTHER half of App Attest,
//  and the one that runs forever rather than once.
//
//  WHY ASSERTIONS DON'T USE AttestationTransport:
//
//                     Attestation          Assertion
//                     ───────────          ─────────
//    Frequency        Once per install     Every session, forever
//    Endpoint         POST /register       POST /session
//    Lives in         Registration flow    App networking layer
//    Control flow     DRIVES a call        DRIVEN BY an existing call
//
//  Routing both through one protocol would drag the entire session layer
//  through an interface designed for a one-time flow, and inverts the
//  dependency direction. See module doc §3.
//
//  MODULE PERFORMS, APP DRIVES: signing needs the keyId (which the app never
//  sees), but *when* and *what* to sign is entirely this file's decision.
//
//  Rewritten against the real server this session — the original version
//  predated the actual Kotlin implementation and used a different, now-wrong
//  wire shape (assertion/nonce as HTTP headers, a `keyId` the app can never
//  actually supply). It also went unwired from HarnessFlowModel.sign()
//  entirely, which is why a real device could show "Assertion Signed" with
//  no `/session` request ever appearing in the server logs — the old sign()
//  fabricated a nonce locally and never called this file at all. See
//  account-keys-reference.md for why /session looks accounts up by
//  account_uuid now, not keyId.
//

import Foundation
import CryptoKit
import AppAttestKit

struct SessionClient {
    let baseURL: URL
    /// Note the type — `AssertionSigning`, not `AttestationCoordinator`. The
    /// session layer only needs to sign; it has no business driving registration.
    let signer: AssertionSigning
    let onEvent: @Sendable (TransportEvent) -> Void

    /// Called once at WebSocket handshake, NOT per message.
    ///
    /// Amortise: verify the assertion once, get a short-lived session token, then
    /// use the token for the rest of the connection. An ECDSA verify per message
    /// would be pointless overhead on both ends.
    func openSession(accountUuid: String) async throws -> String {
        // STEP 2 (app) — obtain a nonce. 60s TTL, much shorter than the
        // registration challenge because nothing is cached against it.
        let nonce = try await fetchNonce()

        // STEP 3 (app) — build the payload hash. The app decides what is
        // being signed; the harness has no real API call to authenticate, so
        // this is a fixed placeholder — a real app would use its actual
        // request body here.
        let body = Data("harness-session-ping".utf8)
        let payloadHash = Data(SHA256.hash(data: nonce + body))

        // STEP 4 (module) — sign. Thin: no I/O, no retries, no observer calls.
        // Throws .notAttested if registration has not completed.
        let assertion = try await signer.sign(payloadHash)

        // STEP 5 (app) — send. One JSON body, matching what the server
        // actually expects — no `keyId` field, since AssertionSigning never
        // exposes one to this call site in the first place.
        let requestBody = SessionRequestBody(
            accountUuid: accountUuid,
            assertion: assertion.base64EncodedString(),
            nonce: nonce.base64EncodedString(),
            body: body.base64EncodedString()
        )
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("session"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(requestBody)

        let data = try await performAuthServerRequest(urlRequest, endpoint: "POST /session", onEvent: onEvent)

        // STEP 6 happens SERVER-SIDE:
        //   1. Nonce valid and unconsumed
        //   2. Recompute SHA256(nonce + body), compare to the assertion's
        //      clientDataHash
        //   3. Verify the ECDSA signature against the stored attest_pubkey
        //   4. Counter STRICTLY GREATER than stored, then persist the new value
        //   5. Issue a short-lived session token
        //
        // The counter is SERVER-SIDE STATE. Apple increments it inside each
        // assertion; the client never tracks it, and the module deliberately
        // has no counter handling. See workflow doc Part 2 step 6.
        let decoded = try JSONDecoder().decode(SessionResponseBody.self, from: data)
        onEvent(.sessionOpened(tokenByteCount: decoded.sessionToken.utf8.count))
        return decoded.sessionToken
    }

    private func fetchNonce() async throws -> Data {
        let url = baseURL.appendingPathComponent("session/nonce")
        let data = try await performAuthServerRequest(URLRequest(url: url), endpoint: "GET /session/nonce", onEvent: onEvent)
        // Same response shape as /challenge — both are "here are 32 random
        // bytes", just with different TTLs server-side.
        let decoded = try JSONDecoder().decode(NonceResponseBody.self, from: data)
        guard let nonce = Data(base64Encoded: decoded.challenge) else {
            throw RealAttestationTransportError.decodingFailed
        }
        return nonce
    }
}

private struct NonceResponseBody: Decodable { let challenge: String }
private struct SessionRequestBody: Encodable {
    let accountUuid: String
    let assertion: String
    let nonce: String
    let body: String
}
private struct SessionResponseBody: Decodable { let sessionToken: String }

// MARK: - Chat, stubbed
//
// Deliberately NOT implemented. The focus here is attestation and assertion.
// What matters is the ORDER: a session token is obtained via assertion BEFORE
// any chat connection is opened.

protocol ChatSession: Sendable {
    func connect(sessionToken: String) async throws
}

struct StubChatSession: ChatSession {
    func connect(sessionToken: String) async throws {
        // Real implementation would open the WebSocket, present the token, and
        // begin the Noise handshake with the peer.
        // Note the ordering the architecture requires:
        //   assertion -> session token -> WebSocket -> Noise handshake -> ratchet
        print("[chat] connected with token \(sessionToken.prefix(8))…")
    }
}

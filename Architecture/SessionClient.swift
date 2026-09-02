import Foundation
import CryptoKit
import AppAttestKit

/// APP-OWNED. Demonstrates the assertion flow — the OTHER half of App Attest,
/// and the one that runs forever rather than once.
///
/// WHY ASSERTIONS DON'T USE AttestationTransport:
///
///                    Attestation          Assertion
///                    ───────────          ─────────
///   Frequency        Once per install     Every session, forever
///   Endpoint         POST /register       POST /session
///   Lives in         Registration flow    App networking layer
///   Control flow     DRIVES a call        DRIVEN BY an existing call
///
/// Routing both through one protocol would drag the entire session layer
/// through an interface designed for a one-time flow, and inverts the
/// dependency direction. See module doc §3.
///
/// MODULE PERFORMS, APP DRIVES: signing needs the keyId (which the app never
/// sees), but *when* and *what* to sign is entirely this file's decision.
struct SessionClient {

    let baseURL: URL
    /// Note the type — `AssertionSigning`, not `AttestationCoordinator`. The
    /// session layer only needs to sign; it has no business driving registration.
    let signer: AssertionSigning

    /// Called once at WebSocket handshake, NOT per message.
    ///
    /// Amortise: verify the assertion once, get a short-lived session token, then
    /// use the token for the rest of the connection. An ECDSA verify per message
    /// would be pointless overhead on both ends.
    func openSession() async throws -> String {
        // STEP 2 (app) — obtain a nonce. 60s TTL, much shorter than the
        // registration challenge because nothing is cached against it.
        let nonce = try await fetchNonce()

        // STEP 3 (app) — build the payload hash. The app decides what is being
        // signed; here it is the nonce plus the request body.
        let body = try JSONEncoder().encode(SessionRequest(
            accountUUID: UserDefaults.standard.string(forKey: "account-uuid") ?? ""))
        let payloadHash = Data(SHA256.hash(data: nonce + body))

        // STEP 4 (module) — sign. Thin: no I/O, no retries, no observer calls.
        // Throws .notAttested if registration has not completed.
        let assertion = try await signer.sign(payloadHash)

        // STEP 5 (app) — send.
        var request = URLRequest(url: baseURL.appendingPathComponent("session"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-Assertion")
        request.setValue(nonce.base64EncodedString(), forHTTPHeaderField: "X-Nonce")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw AttestationError.serverRejected("session rejected")
        }

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
        return try JSONDecoder().decode(SessionResponse.self, from: data).token
    }

    private func fetchNonce() async throws -> Data {
        let (data, _) = try await URLSession.shared.data(
            from: baseURL.appendingPathComponent("session/nonce"))
        let decoded = try JSONDecoder().decode(NonceResponse.self, from: data)
        return Data(base64Encoded: decoded.nonce) ?? Data()
    }
}

private struct NonceResponse: Decodable { let nonce: String }
private struct SessionRequest: Encodable { let accountUUID: String }
private struct SessionResponse: Decodable { let token: String }

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

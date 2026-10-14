//
//  RealAttestationTransport.swift
//  RegistrationKit
//
//  APP-OWNED. Implements `AttestationTransport` against the real Auth
//  Server (AuthServer/). See TransportEvent.swift for why TransportEvent
//  never carries a keyId.
//
//  Wire encoding is standard base64 throughout (not URL-safe): `keyId`
//  arrives from DCAppAttestService.generateKey() as standard base64 already,
//  and the server was built to match that rather than re-encoding it.
//
//  clientDataHash is SHA256(challenge) alone — NOT SHA256(challenge +
//  identityPublicKey). See account-keys-reference.md and
//  AttestationCoordinator's `ensureAttested(binding:)` doc comment for why:
//  the server's verification library fixes that hash formula with no
//  override seam, so the identity binding moved server-side instead (the
//  challenge is issued bound to an identityPublicKey and checked back at
//  /register). The `binding` closure passed to `ensureAttested` must match
//  this — use `Registration.clientDataHash`, which exists so the two cannot
//  disagree.
//

import Foundation
import AppAttestKit

public enum RealAttestationTransportError: Error {
    case decodingFailed
}

public struct RealAttestationTransport: AttestationTransport {
    let baseURL: URL
    /// Read lazily, not captured at construction time — the identity key
    /// may not exist yet when the coordinator (and this transport) is first
    /// resolved, only by the time a request is actually driven through.
    let identityPublicKeyBase64: @Sendable () -> String
    let account: RegisteredAccountStore
    let session: URLSession
    let onEvent: @Sendable (TransportEvent) -> Void

    /// Uses the identity key in `identity`. Never creates one: a key that
    /// vanished mid-flow must surface as a server-side rejection, not be
    /// silently replaced by a new identity. The stores and the session are
    /// parameters for tests only; everything that ships uses the defaults.
    public init(baseURL: URL,
                identity: IdentityKeyStore = .live,
                account: RegisteredAccountStore = .live,
                session: URLSession = .shared,
                onEvent: @escaping @Sendable (TransportEvent) -> Void = { _ in }) {
        self.baseURL = baseURL
        self.account = account
        self.session = session
        self.onEvent = onEvent
        self.identityPublicKeyBase64 = {
            guard let key = (try? identity.loadExisting()) ?? nil else { return "" }
            return key.publicKey.rawRepresentation.base64EncodedString()
        }
    }

    public func fetchChallenge() async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent("challenge"), resolvingAgainstBaseURL: false)!
        // NOT components.queryItems — confirmed via a real device test that it
        // leaves `+` and `/` completely unescaped (only `=` gets percent-
        // encoded). Standard base64 uses `+` in its alphabet, and Ktor (like
        // most web frameworks) decodes an unescaped `+` in a query string as
        // a literal space, following the application/x-www-form-urlencoded
        // convention — even though `+` is technically valid, unescaped, in
        // RFC 3986's own query grammar. Verified directly against Redis: a
        // `+` sent this way arrived on the server as a space, silently
        // corrupting the value. Since the same identityPublicKey travels
        // uncorrupted through /register's JSON body (no such ambiguity in
        // JSON), the two values then mismatch — the `identity_mismatch`
        // failure seen on a real device, intermittent because it only
        // happens when a given key's base64 happens to contain `+`.
        // Percent-encoding it ourselves, escaping everything outside the
        // unreserved set, removes the ambiguity entirely rather than relying
        // on the server happening to interpret it the way we intend.
        var unreserved = CharacterSet.alphanumerics
        unreserved.insert(charactersIn: "-._~")
        let encodedKey = identityPublicKeyBase64().addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
        components.percentEncodedQuery = "identityPublicKey=\(encodedKey)"

        let data = try await performAuthServerRequest(URLRequest(url: components.url!), endpoint: "GET /challenge", session: session, onEvent: onEvent)

        let decoded = try JSONDecoder().decode(ChallengeResponseBody.self, from: data)
        guard let challenge = Data(base64Encoded: decoded.challenge) else {
            throw RealAttestationTransportError.decodingFailed
        }
        onEvent(.challengeFetched(byteCount: challenge.count))
        return challenge
    }

    public func submitAttestation(_ request: AttestationSubmission) async throws -> String {
        let body = RegisterRequestBody(
            keyId: request.keyId,
            challenge: request.challenge.base64EncodedString(),
            attestation: request.attestation.base64EncodedString(),
            identityPublicKey: identityPublicKeyBase64()
        )
        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("register"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(body)

        let data: Data
        do {
            data = try await performAuthServerRequest(urlRequest, endpoint: "POST /register", session: session, onEvent: onEvent)
        } catch AttestationError.serverRejected(let detail) where detail.contains("challenge_invalid_or_expired") {
            // The one rejection the module must hear about specifically (see
            // `AttestationTransport`'s doc comment): the attestation we are
            // resubmitting is bound to a challenge the server no longer
            // holds, and the key behind it can never be attested again.
            // Reported as a plain `.serverRejected`, the coordinator would
            // keep `.attestationPending` and resubmit this dead blob forever.
            // Safe to map unconditionally: /register checks idempotency on
            // keyId BEFORE the challenge (Routes.kt), so an already-registered
            // key never gets this answer.
            throw AttestationError.challengeExpired
        }

        let decoded = try JSONDecoder().decode(RegisterResponseBody.self, from: data)
        // Stored HERE, before returning: the coordinator records "attested"
        // only after this call returns, so there is never a moment where the
        // module says registered and the account id is missing.
        account.current = decoded.accountUuid
        onEvent(.submitted(accountUUID: decoded.accountUuid))
        return decoded.accountUuid
    }

}

private struct ChallengeResponseBody: Decodable {
    let challenge: String
}

private struct RegisterRequestBody: Encodable {
    let keyId: String
    let challenge: String
    let attestation: String
    let identityPublicKey: String
}

private struct RegisterResponseBody: Decodable {
    let accountUuid: String
}

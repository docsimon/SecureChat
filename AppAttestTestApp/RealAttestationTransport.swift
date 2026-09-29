//
//  RealAttestationTransport.swift
//  AppAttestTestApp
//
//  APP-OWNED. Implements `AttestationTransport` against the real Auth
//  Server (AuthServer/), replacing LocalFakeTransport now that the server
//  exists. See LocalFakeTransport.swift for why TransportEvent never
//  carries a keyId — that reasoning is unchanged here.
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
//  /register). The `binding` closure passed to `ensureAttested` in
//  HarnessFlowModel.attest() must match this — it's the app's
//  responsibility, not this transport's, but the two have to agree.
//

import Foundation
import AppAttestKit

enum RealAttestationTransportError: Error {
    case decodingFailed
}

struct RealAttestationTransport: AttestationTransport {
    let baseURL: URL
    /// Read lazily, not captured at construction time — the identity key
    /// may not exist yet when the coordinator (and this transport) is first
    /// resolved, only by the time attest() actually drives a request through.
    let identityPublicKeyBase64: () -> String
    let onEvent: @Sendable (TransportEvent) -> Void

    func fetchChallenge() async throws -> Data {
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

        let (data, response) = try await performRequest(URLRequest(url: components.url!), endpoint: "GET /challenge")

        let decoded = try JSONDecoder().decode(ChallengeResponseBody.self, from: data)
        guard let challenge = Data(base64Encoded: decoded.challenge) else {
            throw RealAttestationTransportError.decodingFailed
        }
        onEvent(.challengeFetched(byteCount: challenge.count))
        return challenge
    }

    func submitAttestation(_ request: AttestationSubmission) async throws -> String {
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

        let (data, _) = try await performRequest(urlRequest, endpoint: "POST /register")

        let decoded = try JSONDecoder().decode(RegisterResponseBody.self, from: data)
        onEvent(.submitted(accountUUID: decoded.accountUuid))
        return decoded.accountUuid
    }

    /// The one place that decides what AttestationCoordinator sees for any
    /// failure here. This matters a lot: the coordinator coerces ANY error
    /// it doesn't recognize as `AttestationError` into `.networkUnavailable`
    /// (AttestationCoordinator.swift's `attemptRegistration`/`submit`) — so
    /// without this distinction, a genuine server-side rejection (bad
    /// identity binding, expired challenge, malformed attestation) would be
    /// indistinguishable in the app's own logs from "couldn't reach the Mac
    /// at all." Confirmed as a real, live gap during a real-device test
    /// session — both looked identical as "networkUnavailable" until this.
    ///
    /// - A true network-layer failure (URLSession itself throws — no
    ///   connection, DNS failure, Local Network permission denied) is logged
    ///   with no status code, then rethrown AS-IS. The coordinator's generic
    ///   catch-all correctly maps this to `.networkUnavailable` — accurate
    ///   in this case.
    /// - An HTTP-level rejection is logged with the real status and body,
    ///   then classified by status code — this split was itself a gap found
    ///   while writing the real-server test checklist, not obvious up front:
    ///   - **4xx** — a definitive business-logic rejection from OUR server
    ///     (bad identity binding, expired challenge, malformed attestation).
    ///     A retry with the same data will never succeed, so this throws
    ///     `AttestationError.serverRejected(...)`, which the coordinator
    ///     passes through UNCHANGED (terminal) rather than coercing.
    ///   - **5xx** — our own server had a transient problem (a DB hiccup,
    ///     for example) that a retry might well resolve once it clears.
    ///     Treating this as terminal would give up on failures that are
    ///     often self-healing, so this throws `AttestationError.retryable(...)`
    ///     instead, which the coordinator retries with backoff like
    ///     `.networkUnavailable`.
    private func performRequest(_ request: URLRequest, endpoint: String) async throws -> (Data, URLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            onEvent(.requestFailed(endpoint: endpoint, statusCode: nil, detail: "\(error)"))
            throw error
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(decoding: data, as: UTF8.self)
            onEvent(.requestFailed(endpoint: endpoint, statusCode: status, detail: body))
            if (500..<600).contains(status) {
                throw AttestationError.retryable("\(endpoint) → HTTP \(status): \(body)")
            }
            throw AttestationError.serverRejected("\(endpoint) → HTTP \(status): \(body)")
        }

        return (data, response)
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

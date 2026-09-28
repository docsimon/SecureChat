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
    case serverError(status: Int, body: String)
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
        components.queryItems = [URLQueryItem(name: "identityPublicKey", value: identityPublicKeyBase64())]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        try Self.checkStatus(response, data: data)

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

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        try Self.checkStatus(response, data: data)

        let decoded = try JSONDecoder().decode(RegisterResponseBody.self, from: data)
        onEvent(.submitted(accountUUID: decoded.accountUuid))
        return decoded.accountUuid
    }

    private static func checkStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw RealAttestationTransportError.serverError(status: status, body: String(decoding: data, as: UTF8.self))
        }
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

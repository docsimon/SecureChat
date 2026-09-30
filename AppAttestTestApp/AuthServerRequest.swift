//
//  AuthServerRequest.swift
//  AppAttestTestApp
//
//  Shared by RealAttestationTransport (registration) and SessionClient
//  (assertion) — both need the same distinction between "never reached the
//  server" and "the server responded and said no", and the same 4xx/5xx
//  split. Extracted here rather than duplicated after SessionClient needed
//  the identical logic RealAttestationTransport already had, tested, and
//  fixed once.
//

import Foundation
import AppAttestKit

/// - A true network-layer failure (URLSession itself throws — no
///   connection, DNS failure, Local Network permission denied) is logged
///   with no status code, then rethrown AS-IS. The coordinator's generic
///   catch-all correctly maps this to `.networkUnavailable`.
/// - A 4xx — a definitive business-logic rejection from our server (bad
///   identity binding, expired challenge/nonce, malformed data, unknown
///   account) — throws `AttestationError.serverRejected(...)`, terminal,
///   not retried.
/// - A 5xx — our own server had a transient problem (a DB hiccup, for
///   example) that a retry might resolve — throws `AttestationError.retryable(...)`
///   instead, retried with backoff like `.networkUnavailable`.
func performAuthServerRequest(
    _ request: URLRequest,
    endpoint: String,
    onEvent: @Sendable (TransportEvent) -> Void
) async throws -> Data {
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

    return data
}

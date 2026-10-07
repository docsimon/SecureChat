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
///
/// What an implementation throws decides what the coordinator does next:
///
///   - `AttestationError.retryable` — the server had a transient problem
///     (5xx). Retried with backoff, same key.
///   - `AttestationError.challengeExpired` — from `submitAttestation` only:
///     the server no longer accepts the challenge this attestation was built
///     on. The key is one-shot and cannot be attested again, so the
///     coordinator discards it and starts over with a new one. **Map your
///     server's "challenge expired/unknown" response to this** — reported as
///     `.serverRejected` instead, the cached attestation is resubmitted on
///     every call forever.
///   - `AttestationError.serverRejected` — a definitive "no". Terminal for
///     this call; state is left where it was.
///   - Anything that is not an `AttestationError` — treated as
///     `.networkUnavailable` and retried with backoff.
public protocol AttestationTransport: Sendable {
    func fetchChallenge() async throws -> Data
    func submitAttestation(_ request: AttestationSubmission) async throws -> String
}

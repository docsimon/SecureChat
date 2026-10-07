//
//  ControllableTransport.swift
//  AppAttestTestApp
//
//  HARNESS-ONLY. Step-by-step control over the registration flow without a
//  single line of harness-specific code inside AppAttestKit.
//
//  The harness drives the SAME `ensureAttested()` the real app will ship —
//  there is no "attest only" or "register only" entry point to test instead
//  of it. In production that flow stops in exactly two ways: the process
//  dies, or a call throws. This wrapper provokes both, at the one seam the
//  app already owns (`AttestationTransport`):
//
//    - PAUSE holds the flow at a network boundary for as long as the tester
//      wants — force-quit, cut the network, stop Docker — then Continue.
//    - FAIL makes the endpoint throw a chosen error, so every error → state
//      row in Architecture/attestation-error-state-table.md can be produced
//      on demand rather than by racing a timing window.
//
//  Apple-side failures (`attestKey`, `generateAssertion`) cannot be injected
//  from here by design — `AttestServicing` is internal to the module. Those
//  come from real conditions (pause AFTER /challenge, enable airplane mode,
//  Continue) or from the package's mock tests.
//

import Foundation
import AppAttestKit

/// What the wrapper does when the coordinator calls one endpoint. Sticky
/// until changed, so a retry loop keeps hitting the same behaviour — flip it
/// back to `.pass` mid-backoff to watch the flow recover by itself. The one
/// exception is `.failChallengeExpired`, which fires once and resets itself.
enum EndpointBehavior: String, CaseIterable, Identifiable, Sendable {
    case pass = "Pass through"
    case pauseBefore = "Pause before sending"
    case pauseAfter = "Pause after the response"
    case failNoConnection = "Fail: no connection"
    case failServerError = "Fail: HTTP 500"
    case failRejected = "Fail: HTTP 400 (rejected)"
    case failChallengeExpired = "Fail: challenge expired"
    case loseResponse = "Send, then lose the response"

    var id: String { rawValue }

    /// `/challenge` has nothing cached against it and no side effect on the
    /// server worth losing, so the last two only make sense for `/register`.
    static let challengeOptions: [EndpointBehavior] =
        [.pass, .pauseBefore, .pauseAfter, .failNoConnection, .failServerError, .failRejected]
    static let registerOptions: [EndpointBehavior] = allCases
}

/// Shared between the UI (which sets behaviours and taps Continue) and the
/// transport (which reads them and waits). In-memory only, deliberately: a
/// force-quit while paused must relaunch into an uncontrolled, pass-through
/// harness, exactly like the real app would.
@Observable @MainActor
final class TransportGate {
    var challengeBehavior: EndpointBehavior = .pass
    var registerBehavior: EndpointBehavior = .pass

    /// Non-nil while a call is being held. Drives the Continue button.
    private(set) var pausedAt: String?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Suspends until `release()`. Also released by cancellation — the
    /// coordinator cancels its in-flight flow on
    /// `acknowledgeKeyInvalidation()` and then WAITS for it, so a pause that
    /// ignored cancellation would deadlock the Danger Zone buttons.
    func pause(at point: String) async {
        pausedAt = point
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume()
                } else {
                    self.continuation = continuation
                }
            }
        } onCancel: {
            Task { @MainActor in self.release() }
        }
        pausedAt = nil
    }

    func release() {
        continuation?.resume()
        continuation = nil
        pausedAt = nil
    }
}

struct ControllableTransport: AttestationTransport {
    let base: AttestationTransport
    let gate: TransportGate
    let onEvent: @Sendable (TransportEvent) -> Void

    func fetchChallenge() async throws -> Data {
        try await perform("GET /challenge", behavior: await gate.challengeBehavior) {
            try await base.fetchChallenge()
        }
    }

    func submitAttestation(_ request: AttestationSubmission) async throws -> String {
        try await perform("POST /register", behavior: await gate.registerBehavior) {
            try await base.submitAttestation(request)
        }
    }

    private func perform<T: Sendable>(
        _ endpoint: String,
        behavior: EndpointBehavior,
        _ call: () async throws -> T
    ) async throws -> T {
        switch behavior {
        case .pass:
            return try await call()

        case .pauseBefore:
            try await hold("before \(endpoint)")
            return try await call()

        case .pauseAfter:
            // The server has already acted on this request; the coordinator
            // has not seen the answer yet. For /register that is the "crash
            // after upload, before response" window.
            let result = try await call()
            try await hold("after \(endpoint) responded")
            return result

        case .failNoConnection:
            injected(endpoint, statusCode: nil, "no connection — nothing was sent")
            throw URLError(.notConnectedToInternet)

        case .failServerError:
            injected(endpoint, statusCode: 500, "nothing was sent")
            throw AttestationError.retryable("\(endpoint) → HTTP 500 (injected)")

        case .failRejected:
            injected(endpoint, statusCode: 400, "nothing was sent")
            throw AttestationError.serverRejected("\(endpoint) → HTTP 400 (injected)")

        case .failChallengeExpired:
            // ONE-SHOT, unlike the others: the coordinator answers this by
            // discarding the key and running the whole flow again in the same
            // call. Left sticky, the fresh key would be "expired" too, and
            // again — up to five real key generations for one tap.
            await MainActor.run { gate.registerBehavior = .pass }
            injected(endpoint, statusCode: 400, "challenge_invalid_or_expired — nothing was sent")
            throw AttestationError.challengeExpired

        case .loseResponse:
            // Really sent, really processed — only the answer is dropped.
            _ = try await call()
            injected(endpoint, statusCode: nil, "request reached the server; its response was discarded")
            throw URLError(.networkConnectionLost)
        }
    }

    private func hold(_ point: String) async throws {
        onEvent(.paused(at: point))
        await gate.pause(at: point)
        // Released by a reset rather than by Continue: stop here instead of
        // carrying on with a request for state that no longer exists.
        try Task.checkCancellation()
        onEvent(.resumed(at: point))
    }

    private func injected(_ endpoint: String, statusCode: Int?, _ detail: String) {
        onEvent(.requestFailed(endpoint: endpoint, statusCode: statusCode,
                               detail: "INJECTED by the harness (Step control) — \(detail)"))
    }
}

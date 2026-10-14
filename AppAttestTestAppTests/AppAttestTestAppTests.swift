//
//  AppAttestTestAppTests.swift
//  AppAttestTestAppTests
//
//  FirstLaunchPurgeGate is the one piece of this session's work where being
//  wrong in a specific direction is catastrophic, not just incorrect: if it
//  ever fires on a normal (non-first) launch instead of only the first one,
//  it repeatedly spends the device's real, finite App Attest key-generation
//  budget until exhausted. These tests exist specifically to guard that
//  asymmetry — not general-purpose coverage, a regression test for the
//  exact failure mode that would be worst.
//

import Testing
import SwiftUI
import AppAttestKit
import RegistrationKit
@testable import AppAttestTestApp

// MARK: - HarnessSession outcome classification
//
// This exact logic has had two real bugs found and fixed this session:
// checking hasFailure before isAttested (mislabeled a successful-after-retry
// session as "Failed"), and not recognizing a restored-into-attested session
// as a success at all (mislabeled it "In progress"). These tests exist
// specifically so a third regression here doesn't slip through unnoticed —
// this is pure, deterministic logic with no external dependencies, exactly
// the kind of thing that should never need a real device to verify.

@Suite("HarnessSession outcome classification")
struct HarnessSessionTests {

    private static func event(_ kind: HarnessEvent.Kind, isError: Bool = false, detail: [DetailField] = []) -> HarnessEvent {
        HarnessEvent(kind: kind, timestamp: Date(), summary: "test", detail: detail, isError: isError)
    }

    private static func restoredEvent(attested: Bool) -> HarnessEvent {
        event(.restored, detail: [DetailField(label: "Restored as attested", value: attested ? "yes" : "no")])
    }

    @Test("Empty session reads as in progress")
    func emptySessionInProgress() {
        let session = HarnessSession()
        #expect(session.outcomeLabel == "In progress")
    }

    @Test("A fresh, successful attestation reads as Attested")
    func freshSuccessIsAttested() {
        var session = HarnessSession()
        session.events = [Self.event(.attestationStarted), Self.event(.attestationStepSubmitted)]

        #expect(session.outcomeLabel == "Attested")
        #expect(session.outcomeColor == .green)
    }

    @Test("REGRESSION: a retryable failure followed by success still reads as Attested, not Failed")
    func successAfterRetryIsAttestedNotFailed() {
        var session = HarnessSession()
        session.events = [
            Self.event(.attestationStarted),
            Self.event(.attestationFailed, isError: true),  // the retry blip
            Self.event(.attestationStepSubmitted)           // then it succeeded
        ]

        #expect(session.outcomeLabel == "Attested (after a retry)")
        #expect(session.outcomeColor == .green) // NOT .red — this is the exact bug that shipped once
    }

    @Test("REGRESSION: a successful attestation followed by a LATER, unrelated Sign failure must not read as plain success")
    func signFailureAfterAttestationIsFlagged() {
        var session = HarnessSession()
        session.events = [
            Self.event(.attestationStarted),
            Self.event(.attestationFailed, isError: true),   // retried, same as the clean-success-after-retry case...
            Self.event(.attestationStepSubmitted),           // ...attestation genuinely succeeded...
            Self.event(.signFailed, isError: true)           // ...but THEN Sign failed. Found on a real device:
            // the Sessions screen showed "Attested (after a retry)" here — true about the
            // attestation, but silently hiding that Sign subsequently failed.
        ]

        #expect(session.outcomeLabel == "Attested, but a later Sign failed")
        #expect(session.outcomeColor == .orange) // neither the plain-success green nor the pure-failure red
    }

    @Test("REGRESSION: a Sign failure followed by a LATER successful retry must not stay stuck flagged forever")
    func signFailureFollowedByRetrySucceedingClearsTheFlag() {
        var session = HarnessSession()
        session.events = [
            Self.event(.attestationStepSubmitted),
            Self.event(.signFailed, isError: true),    // first Sign attempt failed...
            Self.event(.assertionSigned)               // ...but a later retry succeeded. Found on a real
            // device immediately after fixing the inverse bug: checking "did a signFailed
            // event ever happen" instead of "was the MOST RECENT one a failure" left this
            // stuck on the warning state even after the user successfully signed again.
        ]

        // NOT plain "Attested" — hasFailure is a blanket check across every
        // event, so the earlier signFailed still makes it true even though
        // lastSignOutcomeIsFailure correctly reads false. "(after a retry)"
        // is honest here (something DID need a retry) even though it's
        // ambiguous about which step — the detail view has the exact
        // sequence. What matters for this regression is the warning state
        // from signFailureAfterAttestationIsFlagged is GONE, not stuck.
        #expect(session.outcomeLabel == "Attested (after a retry)")
        #expect(session.outcomeColor == .green)
    }

    @Test("REGRESSION: a session that only ever restored into an already-attested state reads as Attested (restored), not In progress")
    func restoredAttestedIsNotInProgress() {
        var session = HarnessSession()
        session.events = [Self.restoredEvent(attested: true), Self.event(.assertionSigned)]

        #expect(session.outcomeLabel == "Attested (restored)")
        #expect(session.outcomeColor == .green)
    }

    @Test("Restoring into a NOT-attested state is not mistaken for success")
    func restoredNotAttestedIsNotSuccess() {
        var session = HarnessSession()
        session.events = [Self.restoredEvent(attested: false)]

        #expect(session.outcomeLabel != "Attested (restored)")
        #expect(session.outcomeLabel == "In progress")
    }

    @Test("A pure failure with no eventual success reads as Failed")
    func pureFailureReadsAsFailed() {
        var session = HarnessSession()
        session.events = [Self.event(.attestationStarted), Self.event(.signFailed, isError: true)]

        #expect(session.outcomeLabel == "Failed")
        #expect(session.outcomeColor == .red)
    }

    @Test("A manual reset with no attestation reads as Reset before attesting")
    func resetOnlyReadsAsResetBeforeAttesting() {
        var session = HarnessSession()
        session.events = [Self.event(.moduleReset)]

        #expect(session.outcomeLabel == "Reset before attesting")
    }

    @Test("Priority: success outranks a later reset/close event in the same session")
    func successOutranksLaterReset() {
        var session = HarnessSession()
        session.events = [
            Self.event(.attestationStepSubmitted),
            Self.event(.identityKeyDeleted) // closed out AFTER already succeeding
        ]

        #expect(session.outcomeLabel == "Attested")
    }
}

// MARK: - ControllableTransport (Step control)
//
// The Simulator can never reach this code through the real flow —
// `isSupported` is false there, so `ensureAttested()` ends before any
// transport call. These pin the two behaviours a device session depends on
// blindly: a pause really holds the request back, and a reset (which cancels
// the flow and then WAITS for it) can never deadlock against a pause.

@Suite("ControllableTransport")
@MainActor
struct ControllableTransportTests {

    actor CountingTransport: AttestationTransport {
        private(set) var challengeCalls = 0
        private(set) var submitCalls = 0
        func fetchChallenge() async throws -> Data { challengeCalls += 1; return Data([0x01]) }
        func submitAttestation(_ request: AttestationSubmission) async throws -> String {
            submitCalls += 1
            return "uuid"
        }
    }

    private static let submission = AttestationSubmission(keyId: "k", challenge: Data(), attestation: Data())

    private func make() -> (ControllableTransport, CountingTransport, TransportGate) {
        let base = CountingTransport()
        let gate = TransportGate()
        return (ControllableTransport(base: base, gate: gate, onEvent: { _ in }), base, gate)
    }

    private func waitUntilPaused(_ gate: TransportGate) async {
        while gate.pausedAt == nil { await Task.yield() }
    }

    @Test("Pause before sending holds the request until released", .timeLimit(.minutes(1)))
    func pauseBeforeHoldsRequest() async throws {
        let (transport, base, gate) = make()
        gate.challengeBehavior = .pauseBefore

        let call = Task { try await transport.fetchChallenge() }
        await waitUntilPaused(gate)
        #expect(await base.challengeCalls == 0)

        gate.release()
        #expect(try await call.value == Data([0x01]))
        #expect(await base.challengeCalls == 1)
        #expect(gate.pausedAt == nil)
    }

    @Test("Pause after the response: the server was reached, the caller has not heard yet", .timeLimit(.minutes(1)))
    func pauseAfterHoldsResponse() async throws {
        let (transport, base, gate) = make()
        gate.registerBehavior = .pauseAfter

        let call = Task { try await transport.submitAttestation(Self.submission) }
        await waitUntilPaused(gate)
        #expect(await base.submitCalls == 1)

        gate.release()
        #expect(try await call.value == "uuid")
    }

    @Test("Cancelling a paused call releases it and sends nothing", .timeLimit(.minutes(1)))
    func cancellationReleasesPause() async throws {
        let (transport, base, gate) = make()
        gate.registerBehavior = .pauseBefore

        let call = Task { try await transport.submitAttestation(Self.submission) }
        await waitUntilPaused(gate)
        call.cancel()

        await #expect(throws: CancellationError.self) { try await call.value }
        #expect(await base.submitCalls == 0)
        #expect(gate.pausedAt == nil)
    }

    @Test("Injected failures throw the error the coordinator branches on, without sending")
    func injectedFailures() async throws {
        let (transport, base, gate) = make()

        gate.registerBehavior = .failChallengeExpired
        await #expect(throws: AttestationError.challengeExpired) {
            try await transport.submitAttestation(Self.submission)
        }
        // One-shot: a sticky "expired" would burn a new key per retry.
        #expect(gate.registerBehavior == .pass)

        gate.registerBehavior = .failRejected
        await #expect(throws: AttestationError.self) {
            try await transport.submitAttestation(Self.submission)
        }
        gate.challengeBehavior = .failNoConnection
        await #expect(throws: URLError.self) { try await transport.fetchChallenge() }

        #expect(await base.submitCalls == 0)
        #expect(await base.challengeCalls == 0)
    }

    @Test("Lose the response: the request is really sent, then a network error is thrown")
    func loseResponseSendsThenThrows() async throws {
        let (transport, base, gate) = make()
        gate.registerBehavior = .loseResponse

        await #expect(throws: URLError.self) { try await transport.submitAttestation(Self.submission) }
        #expect(await base.submitCalls == 1)
    }
}

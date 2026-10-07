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
@testable import AppAttestTestApp

@Suite("FirstLaunchPurgeGate")
struct FirstLaunchPurgeGateTests {

    /// An in-memory stand-in for the UserDefaults flag, so these tests don't
    /// touch real UserDefaults or depend on cleaning up after themselves.
    final class FakeFlag: @unchecked Sendable {
        private(set) var value = false
        func read() -> Bool { value }
        func set() { value = true }
    }

    @Test("First launch runs the purge exactly once")
    func firstLaunchRunsPurge() async {
        let flag = FakeFlag()
        let gate = FirstLaunchPurgeGate(hasRunBefore: flag.read, markAsRun: flag.set)
        var purgeCallCount = 0

        await gate.runIfNeeded { purgeCallCount += 1 }

        #expect(purgeCallCount == 1)
        #expect(flag.read() == true)
    }

    @Test("THE critical case: a normal launch never re-runs the purge")
    func normalLaunchNeverRePurges() async {
        // Simulates the flag already being set from a PREVIOUS launch —
        // exactly the state every ordinary app launch after the first one
        // is in.
        let flag = FakeFlag()
        flag.set()
        let gate = FirstLaunchPurgeGate(hasRunBefore: flag.read, markAsRun: flag.set)
        var purgeCallCount = 0

        await gate.runIfNeeded { purgeCallCount += 1 }

        #expect(purgeCallCount == 0)
    }

    @Test("Simulating many consecutive launches: purge fires on launch 1 only, never on 2 through 10")
    func manyConsecutiveLaunchesPurgeOnlyOnce() async {
        // This is the direct simulation of "does this burn the key budget
        // every launch" — if the gate were broken, purgeCallCount would be
        // 10 here instead of 1.
        let flag = FakeFlag()
        let gate = FirstLaunchPurgeGate(hasRunBefore: flag.read, markAsRun: flag.set)
        var purgeCallCount = 0

        for _ in 1...10 {
            await gate.runIfNeeded { purgeCallCount += 1 }
        }

        #expect(purgeCallCount == 1)
    }

    @Test("markAsRun happens AFTER purge, not before — a crash mid-purge must retry, not skip forever")
    func markAsRunHappensAfterPurge() async {
        let flag = FakeFlag()
        let gate = FirstLaunchPurgeGate(hasRunBefore: flag.read, markAsRun: flag.set)
        var flagWasSetDuringPurge = false

        await gate.runIfNeeded {
            // If markAsRun() ran before this closure, the flag would already
            // read true at this point — it must not.
            flagWasSetDuringPurge = flag.read()
        }

        #expect(flagWasSetDuringPurge == false)
        #expect(flag.read() == true) // set by the time runIfNeeded returns
    }
}

// MARK: - AttestationEnvironmentHint
//
// Pure, deterministic CBOR parsing — no Keychain, no App Attest, no device
// dependency. Verified against a REAL Apple attestation object once already
// this session (the cbor.me cross-check), but that was a one-time manual
// confirmation, not something that protects against a future edit breaking
// the parser. These tests build synthetic-but-valid CBOR fixtures (a real
// attestation object isn't something to embed as a fixture — see the
// keyId-sensitivity notes elsewhere in this project) to lock in the actual
// decoding logic.

@Suite("AttestationEnvironmentHint")
struct AttestationEnvironmentHintTests {

    // MARK: Minimal CBOR encoder, test-fixture-only — NOT the same code as
    // the decoder under test. Building fixtures with independent encoding
    // logic is what makes this a real test of the decoder, not a tautology.

    private static func cborHeader(majorType: UInt8, length: Int) -> Data {
        let major = majorType << 5
        if length <= 23 {
            return Data([major | UInt8(length)])
        } else if length <= 255 {
            return Data([major | 24, UInt8(length)])
        } else {
            let len = UInt16(length)
            return Data([major | 25, UInt8(len >> 8), UInt8(len & 0xFF)])
        }
    }

    private static func cborText(_ s: String) -> Data {
        let utf8 = Data(s.utf8)
        return cborHeader(majorType: 3, length: utf8.count) + utf8
    }

    private static func cborBytes(_ bytes: Data) -> Data {
        cborHeader(majorType: 2, length: bytes.count) + bytes
    }

    private static func cborMap(entryCount: Int) -> Data {
        cborHeader(majorType: 5, length: entryCount)
    }

    /// Builds a valid {fmt, attStmt, authData} attestation object, with a
    /// caller-supplied 16-byte aaguid embedded at the correct offset (byte
    /// 37: rpIdHash 32 + flags 1 + counter 4) inside a realistically-shaped
    /// authData.
    private static func makeAttestationObject(aaguid: Data, authDataLength: Int? = nil) -> Data {
        var authData = Data(repeating: 0xAA, count: 32)        // rpIdHash
        authData.append(0x00)                                   // flags
        authData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // counter
        authData.append(aaguid)                                 // aaguid, 16 bytes
        authData.append(Data(repeating: 0xBB, count: 10))       // trailing bytes, realism only

        if let authDataLength {
            authData = authData.prefix(authDataLength)
        }

        var object = cborMap(entryCount: 3)
        object += cborText("fmt") + cborText("apple-appattest")
        object += cborText("attStmt") + cborMap(entryCount: 0)
        object += cborText("authData") + cborBytes(authData)
        return object
    }

    @Test("Extracts the real aaguid bytes at the correct offset, hex and ASCII both")
    func extractsAAGUIDAtCorrectOffset() {
        let marker = "appattestdevelop"
        let aaguid = Data(marker.utf8) // exactly 16 bytes
        let object = Self.makeAttestationObject(aaguid: aaguid)

        let result = AttestationEnvironmentHint.describe(object)

        // Computed here, not hand-transcribed — a manual hex transcription
        // of this same string is exactly what broke in the first version of
        // this test (miscounted a byte).
        let expectedHex = aaguid.map { String(format: "%02x", $0) }.joined()
        #expect(result.contains(expectedHex))
        #expect(result.contains("\"\(marker)\""))
    }

    @Test("Classifies the environment from the aaguid alone")
    func classifiesEnvironment() {
        let development = Self.makeAttestationObject(aaguid: Data("appattestdevelop".utf8))
        let production = Self.makeAttestationObject(aaguid: Data("appattest".utf8) + Data(repeating: 0, count: 7))
        // The string one secondhand source claimed for development — must NOT
        // be accepted as development just because it looks plausible.
        let lookalike = Self.makeAttestationObject(aaguid: Data("appattestsandbox".utf8))

        #expect(AttestationEnvironmentHint.environment(of: development) == .development)
        #expect(AttestationEnvironmentHint.environment(of: production) == .production)
        #expect(AttestationEnvironmentHint.environment(of: lookalike) == .unrecognised)
        #expect(AttestationEnvironmentHint.environment(of: Data()) == .unrecognised)
    }

    @Test("Non-printable aaguid bytes render as dots in the ASCII column, not garbage or a crash")
    func nonPrintableBytesRenderAsDots() {
        let nonPrintableCount = 3
        let printableCount = 13 // must sum to 16 (the aaguid's fixed length)
        let aaguid = Data(Array(repeating: 0x00, count: nonPrintableCount)
            + Array(repeating: 0x41, count: printableCount)) // 0x41 = 'A'
        let object = Self.makeAttestationObject(aaguid: aaguid)

        let result = AttestationEnvironmentHint.describe(object)

        // Built the expected string the same way, rather than hand-counting
        // characters in a literal — that's exactly the kind of off-by-one
        // this test exists to catch, not introduce.
        let expectedASCII = String(repeating: ".", count: nonPrintableCount)
            + String(repeating: "A", count: printableCount)
        #expect(result.contains("\"\(expectedASCII)\""))
    }

    @Test("authData shorter than 53 bytes is reported, not crashed on")
    func shortAuthDataReportedCleanly() {
        let aaguid = Data(repeating: 0x41, count: 16)
        // 40 bytes total: not enough to contain a full aaguid at offset 37.
        let object = Self.makeAttestationObject(aaguid: aaguid, authDataLength: 40)

        let result = AttestationEnvironmentHint.describe(object)

        #expect(result.contains("too short"))
        #expect(result.contains("40 bytes"))
    }

    @Test("Missing authData key is reported, not crashed on")
    func missingAuthDataKeyReportedCleanly() {
        var object = Self.cborMap(entryCount: 2)
        object += Self.cborText("fmt") + Self.cborText("apple-appattest")
        object += Self.cborText("attStmt") + Self.cborMap(entryCount: 0)
        // No "authData" key at all.

        let result = AttestationEnvironmentHint.describe(object)

        #expect(result.contains("could not parse"))
    }

    @Test("Truncated/malformed CBOR is reported, not crashed on")
    func truncatedCBORReportedCleanly() {
        let aaguid = Data(repeating: 0x41, count: 16)
        let object = Self.makeAttestationObject(aaguid: aaguid)
        let truncated = object.prefix(object.count / 2) // cut off mid-structure

        let result = AttestationEnvironmentHint.describe(Data(truncated))

        #expect(result.contains("could not parse") || result.contains("too short"))
    }

    @Test("Empty data is reported, not crashed on")
    func emptyDataReportedCleanly() {
        let result = AttestationEnvironmentHint.describe(Data())

        #expect(result.contains("could not parse"))
    }
}

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

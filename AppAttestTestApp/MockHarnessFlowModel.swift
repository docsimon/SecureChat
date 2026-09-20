//
//  MockHarnessFlowModel.swift
//  AppAttestTestApp
//
//  Drives MockHarnessFlowView with entirely FAKE data and simulated delays.
//  No AppAttestKit import, no real Apple call, nothing network-touching —
//  this exists purely to evaluate the UX before wiring the approved design
//  to the real AttestationCoordinator / IdentityKeyStore.
//
//  The two-step split mirrors what the real version will actually do:
//  step 1 generates the app-owned X25519 identity key (real, local, separate
//  from Apple), step 2 triggers AttestationCoordinator's one real atomic
//  flow (Apple's own key-gen + attest + submit, internal to the module by
//  design). See appattestkit-module-design.md §3/§4 for why those can't be
//  split any further than this.
//

import Foundation

@Observable @MainActor
final class MockHarnessFlowModel {
    enum ActiveStep { case none, identity, attest, sign }

    private(set) var identityGenerated = false
    private(set) var attested = false
    private(set) var activeStep: ActiveStep = .none
    private(set) var fakeIdentityPrefix: String?

    /// One entry per attempt. "Reset module state" and "Delete identity key"
    /// close out the current session (as its last event) and open a fresh
    /// one — see HarnessSession.swift.
    var sessions: [HarnessSession] = [HarnessSession()]

    var stateLabel: String {
        if attested { return "attested" }
        if identityGenerated { return "identity ready (App Attest not yet requested)" }
        return "none"
    }

    func generateIdentity() async {
        activeStep = .identity
        defer { activeStep = .none }

        try? await Task.sleep(for: .milliseconds(300))
        let prefix = Self.randomHex(4)
        fakeIdentityPrefix = prefix
        identityGenerated = true
        log(.identityKeyGenerated, summary: "identity key ready (\(prefix)…)",
            detail: [DetailField(label: "Public key prefix", value: prefix)])
    }

    func attest() async {
        activeStep = .attest
        defer { activeStep = .none }

        log(.attestationStarted, summary: "attestation flow started")

        try? await Task.sleep(for: .milliseconds(300))
        let challenge = Self.randomHex(16)
        log(.attestationStepChallenge, summary: "GET /challenge → 32 random bytes",
            detail: [DetailField(label: "Challenge", value: challenge)])

        try? await Task.sleep(for: .milliseconds(300))
        let fakeKeyId = Self.randomHex(16)
        log(.attestationStepKeyGenerated, summary: "App Attest key generated — no network involved",
            detail: [DetailField(label: "keyId (hash)", value: fakeKeyId)])

        try? await Task.sleep(for: .milliseconds(500))
        log(.attestationStepAttested, summary: "CBOR attestation object received (312 bytes)",
            detail: [
                DetailField(label: "Format", value: "CBOR — {fmt, attStmt, authData}"),
                DetailField(label: "Attestation object size", value: "312 bytes"),
                DetailField(label: "aaguid", value: "(placeholder — see AttestationEnvironmentHint.swift for the real extractor)")
            ])

        try? await Task.sleep(for: .milliseconds(300))
        let uuid = UUID().uuidString
        log(.attestationStepSubmitted, summary: "POST /register → Auth Server",
            detail: [DetailField(label: "Account UUID", value: uuid)])

        attested = true
    }

    func sign() async {
        activeStep = .sign
        defer { activeStep = .none }

        try? await Task.sleep(for: .milliseconds(200))
        log(.assertionSigned, summary: "assertion signed (64 bytes)",
            detail: [DetailField(label: "Signature size", value: "64 bytes")])
    }

    func simulateFailure() {
        log(.attestationFailed, summary: "retryable (serverUnavailable), attempt 1", isError: true)
    }

    /// Matches Option A (appattestkit-module-design.md §8): resetting module
    /// state does NOT touch the identity key.
    func resetModuleState() {
        attested = false
        log(.moduleReset, summary: "module state cleared — identity key kept, matches Option A")
        startNewSession()
    }

    func deleteIdentityKey() {
        identityGenerated = false
        attested = false
        fakeIdentityPrefix = nil
        log(.identityKeyDeleted, summary: "identity key deleted — next run starts fully fresh")
        startNewSession()
    }

    private func log(_ kind: HarnessEvent.Kind, summary: String, detail: [DetailField] = [], isError: Bool = false) {
        let event = HarnessEvent(kind: kind, timestamp: Date(), summary: summary, detail: detail, isError: isError)
        sessions[sessions.count - 1].events.append(event)
    }

    private func startNewSession() {
        sessions.append(HarnessSession())
    }

    private static func randomHex(_ byteCount: Int) -> String {
        (0..<byteCount).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

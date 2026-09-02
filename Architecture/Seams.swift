import Foundation
import DeviceCheck

// MARK: - Internal seams (module → system)
//
// These are `internal`, NOT public. They exist purely for testability, and tests
// live inside this package (`@testable import AppAttestKit` reaches internal types).
//
// Keeping them internal means the app CANNOT reach around the coordinator to call
// `attestKey` directly or write a keyId itself — which is exactly the mistake the
// state machine exists to prevent. See module doc §3.

/// Seam over `DCAppAttestService`, which is a concrete class that cannot be
/// subclassed or stubbed and only returns errors on real hardware.
protocol AttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// Seam over persistence. The module owns `keyId` storage because it owns the
/// "retry with the same keyId" rule — if the app held it, that rule would not
/// be enforceable. Also caches the attestation object (see AttestationState).
protocol AttestationKeyStore: Sendable {
    func loadKeyId() throws -> String?
    func store(keyId: String) throws
    /// Records that the SERVER confirmed registration. Without this, a relaunch
    /// cannot distinguish "key generated, never attested" from "fully registered",
    /// and would try to re-attest a one-shot key — burning a key regeneration and
    /// eventually locking the user out.
    func loadIsAttested() throws -> Bool
    func store(isAttested: Bool) throws
    func loadAttestation() throws -> (object: Data, challenge: Data)?
    func store(attestation: Data, challenge: Data) throws
    func clearAttestation() throws
    /// Persisted across launches so a bug cannot loop and burn the device's
    /// lifetime key budget.
    func loadRegenerationCount() throws -> Int
    func store(regenerationCount: Int) throws
    func clear() throws
}

// MARK: - Public seams (module → app)

/// The module never knows a URL. The app implements this against its endpoints.
///
/// Scoped to the ONE-TIME registration flow only. Assertions do NOT go through
/// here — they have a different lifetime and inverted control flow. See `AssertionSigning`.
public protocol AttestationTransport: Sendable {
    func fetchChallenge() async throws -> Data
    func submitAttestation(_ request: AttestationSubmission) async throws -> String
}

/// What the app POSTs to `/register`. Every field is a PUBLIC credential —
/// private keys never leave the device — so TLS in transit is sufficient and no
/// application-layer encryption is needed. See module doc §2a.
public struct AttestationSubmission: Sendable {
    public let keyId: String
    public let challenge: Data
    public let attestation: Data

    public init(keyId: String, challenge: Data, attestation: Data) {
        self.keyId = keyId
        self.challenge = challenge
        self.attestation = attestation
    }

    // NOTE: the identity public key is NOT here. The app already holds it and
    // adds it when serialising this to its own wire format — the module has no
    // reason to carry app protocol data through its own types.
}

/// Passive notification sink. The coordinator calls it; the module does nothing
/// with the calls. The app decides whether that means logging or analytics.
///
/// DO NOT drive UI from this — it fires from actor context and would need an
/// explicit MainActor hop. Have the view model read coordinator state instead.
public protocol AttestationObserver: Sendable {
    func didTransition(to state: AttestationState)
    func didFail(_ error: AttestationError, attempt: Int)
}

// MARK: - Public seam (app → module)

/// Assertions are deliberately NOT routed through `AttestationTransport`:
/// attestation DRIVES a network call, whereas an assertion is DRIVEN BY a
/// network call the app already makes. Merging them would drag the entire
/// session layer through an interface designed for a one-time flow.
///
/// Module PERFORMS, app DRIVES: signing needs the keyId (which the app never
/// sees), but *when* and *what* to sign is entirely the app's decision.
public protocol AssertionSigning: Sendable {
    func sign(_ payload: Data) async throws -> Data
}

//
//  InMemoryKeyStore.swift
//  AppAttestKitTests
//
//  Test double for `AttestationKeyStore`. Keychain/file I/O (what
//  `LiveKeyStore` uses) is as untestable in CI as `DCAppAttestService` itself
//  — this is what lets the state machine's persistence/resumption logic be
//  exercised without either (module doc §3, §9).
//

import Foundation
@testable import AppAttestKit

/// A plain class with a lock, NOT an actor.
///
/// `AttestationKeyStore`'s requirements are synchronous (`throws`, not
/// `async throws`) — matching how `LiveKeyStore` actually works, since
/// Keychain and file-system calls are synchronous. An actor's isolated
/// methods can't satisfy a *synchronous* protocol requirement (the compiler
/// rejects it under strict concurrency: an outside caller can't invoke an
/// actor-isolated method without `await`). A lock-protected class is the
/// correct shape here, mirroring `MockObserver` for the same reason.
final class InMemoryKeyStore: AttestationKeyStore, @unchecked Sendable {

    private let lock = NSLock()
    private var keyId: String?
    private var isAttested = false
    private var cached: (object: Data, challenge: Data)?

    /// Seeds the store as if a previous run got partway through the flow
    /// before crashing — used by the "resume after crash" tests to start
    /// `restore()` from a specific mid-flow state instead of driving the
    /// whole flow just to get there.
    init(keyId: String? = nil,
         isAttested: Bool = false,
         cachedAttestation: (object: Data, challenge: Data)? = nil) {
        self.keyId = keyId
        self.isAttested = isAttested
        self.cached = cachedAttestation
    }

    func loadKeyId() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return keyId
    }

    func store(keyId: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.keyId = keyId
    }

    func loadIsAttested() throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return isAttested
    }

    /// When true, `store(isAttested:)` throws — simulates the Keychain write
    /// failing right after the server confirmed registration.
    var failsIsAttestedWrites: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _failsIsAttestedWrites }
        set { lock.lock(); defer { lock.unlock() }; _failsIsAttestedWrites = newValue }
    }
    private var _failsIsAttestedWrites = false

    struct WriteFailure: Error {}

    func store(isAttested: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        if _failsIsAttestedWrites { throw WriteFailure() }
        self.isAttested = isAttested
    }

    func loadAttestation() throws -> (object: Data, challenge: Data)? {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func store(attestation: Data, challenge: Data) throws {
        lock.lock(); defer { lock.unlock() }
        cached = (attestation, challenge)
    }

    func clearAttestation() throws {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }

    /// Mirrors `LiveKeyStore.clear()`.
    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        keyId = nil
        isAttested = false
        cached = nil
    }
}

//
//  MockAttestService.swift
//  AppAttestKitTests
//
//  Test double for `AttestServicing` — stands in for `DCAppAttestService`,
//  which is a concrete class that can't be subclassed and only errors on
//  real hardware (module doc §3). Lets tests script exactly which failure
//  happens on which call, which is the whole point: the retry/regeneration
//  rules in `AttestationCoordinator` are the thing under test.
//

import Foundation
@testable import AppAttestKit

/// An `actor`, not a class. `generateKey`/`attestKey`/`generateAssertion` are
/// all `async` in the protocol, so actor isolation gives thread-safe mutable
/// state (call counts, queued results) for free — no manual locking, and no
/// `@unchecked Sendable` escape hatch needed. `isSupported` is the protocol's
/// one *synchronous* requirement, so it's fixed at init as a `nonisolated let`
/// (tests that need it to change mid-run can just make a second mock).
actor MockAttestService: AttestServicing {

    nonisolated let isSupported: Bool

    private(set) var generateKeyCallCount = 0
    private(set) var attestKeyCallCount = 0
    private(set) var generateAssertionCallCount = 0

    /// Every keyId this mock has ever handed out, in order — lets a test
    /// assert "regenerated exactly once" by checking for two distinct ids
    /// rather than just a call count.
    private(set) var issuedKeyIds: [String] = []

    /// Queued outcomes, consumed one per call. Once only one is left it keeps
    /// repeating — most tests only care about "fails N times then succeeds"
    /// and shouldn't have to pad the array with the same success forever.
    private var generateKeyResults: [Result<String, Error>]
    private var attestKeyResults: [Result<Data, Error>]
    private var generateAssertionResults: [Result<Data, Error>]

    init(isSupported: Bool = true,
         generateKeyResults: [Result<String, Error>] = [.success("mock-key-id")],
         attestKeyResults: [Result<Data, Error>] = [.success(Data([0x01]))],
         generateAssertionResults: [Result<Data, Error>] = [.success(Data([0x02]))]) {
        self.isSupported = isSupported
        self.generateKeyResults = generateKeyResults
        self.attestKeyResults = attestKeyResults
        self.generateAssertionResults = generateAssertionResults
    }

    func generateKey() async throws -> String {
        generateKeyCallCount += 1
        let keyId = try consume(&generateKeyResults)
        issuedKeyIds.append(keyId)
        return keyId
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        attestKeyCallCount += 1
        return try consume(&attestKeyResults)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        generateAssertionCallCount += 1
        return try consume(&generateAssertionResults)
    }

    private func consume<T>(_ queue: inout [Result<T, Error>]) throws -> T {
        precondition(!queue.isEmpty, "MockAttestService: no result queued for this call")
        let result = queue.count > 1 ? queue.removeFirst() : queue[0]
        return try result.get()
    }
}

/// A generic stand-in for "Apple returned some other NSError", used to test
/// `AttestationError.from(_:)`'s fallback branch without depending on a real
/// `DCError` case.
struct GenericNetworkError: Error {}

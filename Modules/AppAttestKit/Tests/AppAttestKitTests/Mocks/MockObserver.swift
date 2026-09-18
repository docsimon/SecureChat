//
//  MockObserver.swift
//  AppAttestKitTests
//
//  Test double for `AttestationObserver`, which is the module's window into
//  otherwise-silent failures (module doc §3) — these tests are what confirm
//  it actually fires, and in the right order.
//

import Foundation
@testable import AppAttestKit

/// A plain class with a lock, NOT an actor — deliberately different from the
/// other three mocks.
///
/// `AttestationObserver`'s methods are synchronous by design (the doc-comment
/// on the protocol itself warns against driving UI from it without an
/// explicit hop). The coordinator calls them in-line, synchronously, from its
/// own actor-isolated code. If this mock were an actor, recording a call
/// would require hopping to the actor's executor via an unstructured
/// `Task { }`, and a test doing `await coordinator.ensureAttested()` then
/// immediately asserting on `observer.transitions` could race against that
/// hop and see a stale (too-short) array. A lock keeps recording synchronous,
/// matching how the coordinator actually calls it.
final class MockObserver: AttestationObserver, @unchecked Sendable {

    private let lock = NSLock()
    private var _transitions: [AttestationState] = []
    private var _failures: [(error: AttestationError, attempt: Int)] = []

    var transitions: [AttestationState] {
        lock.lock(); defer { lock.unlock() }
        return _transitions
    }

    var failures: [(error: AttestationError, attempt: Int)] {
        lock.lock(); defer { lock.unlock() }
        return _failures
    }

    func didTransition(to state: AttestationState) {
        lock.lock(); defer { lock.unlock() }
        _transitions.append(state)
    }

    func didFail(_ error: AttestationError, attempt: Int) {
        lock.lock(); defer { lock.unlock() }
        _failures.append((error, attempt))
    }
}

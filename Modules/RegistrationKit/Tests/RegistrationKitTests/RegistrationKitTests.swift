//
//  RegistrationKitTests.swift
//  RegistrationKitTests
//

import Foundation
import Testing
@testable import RegistrationKit

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

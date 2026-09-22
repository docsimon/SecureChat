//
//  FirstLaunchPurgeGate.swift
//  AppAttestTestApp
//
//  Runs a purge action at most once per install lifetime, gated by a flag
//  that survives app updates but NOT reinstalls — UserDefaults lives in the
//  app's sandbox container, wiped on delete, unlike Keychain
//  (architecture-decisions.md §8's original note on this exact pattern).
//
//  Extracted as its own small, injectable type — not left inline in
//  HarnessFlowModel — specifically so the gating logic has its own
//  regression test (FirstLaunchPurgeGateTests). Getting this wrong in either
//  direction is bad, but getting it wrong in ONE specific direction is the
//  worst bug this whole session has touched: if `hasRunBefore` is ever
//  wrong and reports `false` on a normal (non-first) launch, `purge` fires
//  on every single launch, repeatedly spending the device's real, finite
//  App Attest key-generation budget until it's exhausted. Getting it wrong
//  the other way (never firing) is merely annoying — stale state sits
//  unpurged. The asymmetry is why this has a dedicated test rather than
//  just "seems to work" from manual testing.
//

import Foundation

struct FirstLaunchPurgeGate {
    var hasRunBefore: () -> Bool
    var markAsRun: () -> Void

    /// Runs `purge` only if `hasRunBefore()` is false, then calls
    /// `markAsRun()` — deliberately AFTER `purge` completes, not before, so
    /// a crash mid-purge retries the (idempotent, safe) purge on the next
    /// launch instead of silently marking itself "done" and skipping it
    /// forever.
    func runIfNeeded(_ purge: () async -> Void) async {
        guard !hasRunBefore() else { return }
        await purge()
        markAsRun()
    }
}

extension FirstLaunchPurgeGate {
    /// Production wiring: backed by `UserDefaults.standard`.
    static func standard(key: String) -> FirstLaunchPurgeGate {
        FirstLaunchPurgeGate(
            hasRunBefore: { UserDefaults.standard.bool(forKey: key) },
            markAsRun: { UserDefaults.standard.set(true, forKey: key) }
        )
    }
}

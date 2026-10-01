//
//  RegisteredAccountStore.swift
//  AppAttestTestApp
//
//  The account UUID handed back by a successful /register — app-owned data
//  (architecture-decisions.md: "Client stores the UUID"), not part of the
//  module's own Keychain-backed state. UserDefaults, not Keychain: unlike
//  keyId/isAttested (which deliberately SURVIVE reinstall so the purge gate
//  can detect and clean up a stale registration), this
//  value should track the CURRENT registration 1:1 — cleared everywhere the
//  harness clears module state, never meant to outlive it. Needed because
//  /session looks accounts up by this now, not keyId — see
//  account-keys-reference.md for why the module's own AssertionSigning
//  protocol can never hand the app a keyId to use instead.
//

import Foundation

enum RegisteredAccountStore {
    private static let key = "harness.registeredAccountUUID"

    static var current: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

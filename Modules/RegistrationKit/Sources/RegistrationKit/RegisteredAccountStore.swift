//
//  RegisteredAccountStore.swift
//  RegistrationKit
//
//  The account UUID handed back by a successful /register — app-owned data
//  (architecture-decisions.md: "Client stores the UUID"), not part of the
//  module's own Keychain-backed state. UserDefaults, not Keychain: unlike
//  keyId/isAttested (which deliberately SURVIVE reinstall so the purge gate
//  can detect and clean up a stale registration), this
//  value should track the CURRENT registration 1:1 — cleared everywhere
//  module state is cleared, never meant to outlive it. Needed because
//  /session looks accounts up by this now, not keyId — see
//  account-keys-reference.md for why the module's own AssertionSigning
//  protocol can never hand the app a keyId to use instead.
//

import Foundation

public struct RegisteredAccountStore: @unchecked Sendable {
    private static let key = "registrationkit.accountUUID"

    /// `UserDefaults.standard` — what every build that ships uses.
    public static let live = RegisteredAccountStore(defaults: .standard)

    // UserDefaults is thread-safe; it is not marked Sendable in every SDK.
    private let defaults: UserDefaults

    /// Tests pass a throwaway suite so they never touch the real value.
    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var current: String? {
        get { defaults.string(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}

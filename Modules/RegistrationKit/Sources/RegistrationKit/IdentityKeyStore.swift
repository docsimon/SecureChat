//
//  IdentityKeyStore.swift
//  RegistrationKit
//
//  APP-OWNED, not part of AppAttestKit. This is the X25519 identity keypair
//  from architecture-decisions.md §4 and account-keys-reference.md — the
//  thing the App Attest key's clientDataHash binds to
//  (`SHA256(challenge ‖ identityPublicKey)`), and the key that survives a
//  `.keyInvalid` reset under the Option A decision in
//  appattestkit-module-design.md §8.
//

import Foundation
import CryptoKit
import Security

/// Loads the identity keypair if one exists, or generates and persists one.
/// Idempotent — safe to call on every launch.
///
/// A value, not a set of static functions, so tests can run registration
/// end to end against `inMemory()` instead of the real Keychain (on a phone
/// the real one holds an actual registration). Everything that ships uses
/// `live`.
public struct IdentityKeyStore: Sendable {

    private let read: @Sendable () throws -> Data?
    private let write: @Sendable (Data) throws -> Void
    private let remove: @Sendable () -> Void

    /// The Keychain item every build that ships uses.
    public static let live = IdentityKeyStore(read: Keychain.read, write: Keychain.write, remove: Keychain.delete)

#if DEBUG
    /// Tests only: a store that lives as long as the value and touches nothing.
    @_spi(Testing)
    public static func inMemory() -> IdentityKeyStore {
        let box = LockedBox()
        return IdentityKeyStore(read: { box.value }, write: { box.value = $0 }, remove: { box.value = nil })
    }
#endif

    public func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try loadExisting() {
            return existing
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try write(key.rawRepresentation)
        return key
    }

    /// Read-only — never generates. Needed so the UI can correctly reflect
    /// "identity already exists" on launch (e.g. after a real kill-and-
    /// relaunch) without silently creating one just by checking.
    public func exists() -> Bool {
        // Since Swift 5 (SE-0230), `try?` on a call that already returns an
        // optional flattens automatically — no double-optional here. A
        // thrown error and a genuine "no key stored" both collapse to nil,
        // which is fine for this check: either way, the answer is "no
        // identity key to reflect in the UI yet."
        (try? loadExisting()) != nil
    }

    /// Read-only — never generates. Use this anywhere a missing key is an
    /// error to report rather than something to silently paper over with a
    /// brand-new identity (e.g. while a registration is already in flight).
    public func loadExisting() throws -> Curve25519.KeyAgreement.PrivateKey? {
        guard let data = try read() else { return nil }
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    /// Only ever together with the App Attest state (v1 policy,
    /// appattestkit-module-design.md §8): the first-launch purge, a dead App
    /// Attest key, or a deliberate reset.
    public func delete() {
        remove()
    }
}

private enum Keychain {

    static let service = "com.securechat.registrationkit.identity"
    static let account = "identityKey"

    @Sendable static func read() throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    @Sendable static func write(_ data: Data) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Same accessibility as the production identity key
            // (architecture doc §2): available only while unlocked, and
            // excluded from being decryptable after an iCloud backup
            // restore to a different device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    @Sendable static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

#if DEBUG
private final class LockedBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _value: Data?
    var value: Data? {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); defer { lock.unlock() }; _value = newValue }
    }
}
#endif

private struct KeychainError: Error {
    let status: OSStatus
}

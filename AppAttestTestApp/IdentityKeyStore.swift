//
//  IdentityKeyStore.swift
//  AppAttestTestApp
//
//  APP-OWNED, not part of AppAttestKit. This is the X25519 identity keypair
//  from architecture-decisions.md §4 and account-keys-reference.md — the
//  thing the App Attest key's clientDataHash binds to
//  (`SHA256(challenge ‖ identityPublicKey)`), and the key that survives a
//  `.keyInvalid` reset under the Option A decision in
//  appattestkit-module-design.md §8.
//
//  Written for real here, not as a throwaway: this is the same shape the
//  eventual RegistrationFeature layer needs (module doc §2's layering), so
//  nothing here is wasted once that layer exists.
//

import Foundation
import CryptoKit
import Security

/// Loads the identity keypair if one exists, or generates and persists one.
/// Idempotent — safe to call on every launch.
enum IdentityKeyStore {

    private static let service = "com.securechat.appattesttestapp.identity"
    private static let account = "identityKey"

    static func loadOrCreate() throws -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = try load() {
            return existing
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        try store(key)
        return key
    }

    /// Read-only — never generates. Needed so the UI can correctly reflect
    /// "identity already exists" on launch (e.g. after a real kill-and-
    /// relaunch) without silently creating one just by checking.
    static func exists() -> Bool {
        // Since Swift 5 (SE-0230), `try?` on a call that already returns an
        // optional flattens automatically — no double-optional here. A
        // thrown error and a genuine "no key stored" both collapse to nil,
        // which is fine for this check: either way, the answer is "no
        // identity key to reflect in the UI yet."
        (try? load()) != nil
    }

    private static func load() throws -> Curve25519.KeyAgreement.PrivateKey? {
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
            guard let data = result as? Data else { return nil }
            return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    private static func store(_ key: Curve25519.KeyAgreement.PrivateKey) throws {
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.rawRepresentation,
            // Same accessibility as the production identity key
            // (architecture doc §2): available only while unlocked, and
            // excluded from being decryptable after an iCloud backup
            // restore to a different device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    /// Test-harness only — the real app never deletes the identity key except
    /// on deliberate factory-reset/logout (appattestkit-module-design.md §8).
    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct KeychainError: Error {
    let status: OSStatus
}

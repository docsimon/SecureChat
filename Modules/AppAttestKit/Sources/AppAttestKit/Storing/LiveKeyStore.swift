//
//  LiveKeyStore.swift
//  AppAttestKit
//
//  Created by Simone Barbara on 02/09/2026.
//

import Foundation
import Security

/// Production implementation of `AttestationKeyStore`.
///
/// Splits storage across two backends, matching the two different sensitivity
/// levels called out in the docs:
///
///   - **Keychain** — `keyId`, the "server confirmed" flag, and the
///     regeneration counter. Small values, and `keyId` in particular is a
///     persistent per-device identifier (architecture doc §10), which is
///     exactly what the Keychain's access-control model is for.
///   - **A file in Application Support** — the cached attestation object +
///     the challenge it was built from. ~5KB, too large to be a good Keychain
///     fit, and — importantly — the attestation object is a PUBLIC credential
///     (workflow doc step 9), not a secret. `NSFileProtectionComplete` (via
///     `.completeFileProtection`) is the right protection level: unreadable
///     while the device is locked, but no Keychain ceremony needed.
///
/// `struct` + no mutable stored properties (`service` is a constant) means
/// this satisfies `Sendable` for free — there is no shared mutable state to
/// race on, every call opens/closes its own Keychain/file handle.
struct LiveKeyStore: AttestationKeyStore {

    /// Keychain items are namespaced under this service string so this store
    /// can never collide with anything else the app puts in the Keychain.
    private let service = "com.securechat.appattestkit"

    private enum Account {
        static let keyId = "keyId"
        static let isAttested = "isAttested"
        static let regenerationCount = "regenerationCount"
    }

    // MARK: AttestationKeyStore — keyId

    func loadKeyId() throws -> String? {
        try loadString(account: Account.keyId)
    }

    func store(keyId: String) throws {
        try storeString(keyId, account: Account.keyId)
    }

    // MARK: AttestationKeyStore — "server confirmed" flag

    func loadIsAttested() throws -> Bool {
        try loadString(account: Account.isAttested) == "true"
    }

    func store(isAttested: Bool) throws {
        try storeString(isAttested ? "true" : "false", account: Account.isAttested)
    }

    // MARK: AttestationKeyStore — regeneration counter
    //
    // NOTE: deliberately never touched by `clear()` below. See the comment
    // there — resetting this on every clear would defeat the entire point of
    // persisting it.

    func loadRegenerationCount() throws -> Int {
        guard let raw = try loadString(account: Account.regenerationCount),
              let count = Int(raw) else { return 0 }
        return count
    }

    func store(regenerationCount: Int) throws {
        try storeString(String(regenerationCount), account: Account.regenerationCount)
    }

    // MARK: AttestationKeyStore — cached attestation (file-backed)

    func loadAttestation() throws -> (object: Data, challenge: Data)? {
        guard FileManager.default.fileExists(atPath: try attestationFileURL().path) else {
            return nil
        }
        let data = try Data(contentsOf: try attestationFileURL())
        let cached = try JSONDecoder().decode(CachedAttestation.self, from: data)
        return (cached.object, cached.challenge)
    }

    func store(attestation: Data, challenge: Data) throws {
        let directory = try attestationDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = CachedAttestation(object: attestation, challenge: challenge)
        let data = try JSONEncoder().encode(cached)
        // `.completeFileProtection` is the Data-API equivalent of setting
        // NSFileProtectionComplete on the file — unreadable while the device
        // is locked, matching the workflow doc's requirement for this file.
        try data.write(to: try attestationFileURL(), options: .completeFileProtection)
    }

    func clearAttestation() throws {
        let url = try attestationFileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: AttestationKeyStore — full reset

    /// Wipes `keyId`, the attested flag, and the cached attestation.
    ///
    /// Deliberately does **not** touch `regenerationCount`. This is called
    /// right after a `keyInvalid`/`challengeExpired` failure to discard the
    /// dead key (module doc §7) — but the counter exists specifically to
    /// survive that reset, so a crash-loop through this exact path can't
    /// silently re-arm the device's lifetime key budget. See `AttestationKeyStore`.
    func clear() throws {
        try deleteItem(account: Account.keyId)
        try deleteItem(account: Account.isAttested)
        try clearAttestation()
    }

    // MARK: Keychain plumbing
    //
    // Generic-password items, keyed by (service, account). Writes are
    // delete-then-add rather than SecItemUpdate — one code path instead of
    // two, and simplicity matters more than the extra syscall for values this
    // small and this infrequently written.

    private func storeString(_ value: String, account: String) throws {
        try storeData(Data(value.utf8), account: account)
    }

    private func loadString(account: String) throws -> String? {
        guard let data = try loadData(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func storeData(_ data: Data, account: String) throws {
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Matches the identity key's accessibility (architecture doc §2):
            // available only while unlocked, and never included in an iCloud
            // backup restore to a different device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func loadData(account: String) throws -> Data? {
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

    private func deleteItem(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    // MARK: File plumbing

    private struct CachedAttestation: Codable {
        let object: Data
        let challenge: Data
    }

    private func attestationDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return appSupport.appendingPathComponent("AppAttestKit", isDirectory: true)
    }

    private func attestationFileURL() throws -> URL {
        try attestationDirectory().appendingPathComponent("cached-attestation.json")
    }
}

/// `OSStatus` doesn't conform to `Error` on its own, so Keychain failures need
/// a wrapper to be thrown. Kept minimal — this is a plumbing error, not
/// something calling code branches on (the app policy is set by
/// `AttestationError`, one layer up).
struct KeychainError: Error {
    let status: OSStatus
}

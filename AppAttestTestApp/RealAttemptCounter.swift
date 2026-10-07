//
//  RealAttemptCounter.swift
//  AppAttestTestApp
//
//  Tracks real generateKey() calls this device has EVER made — deliberately
//  Keychain-backed, not UserDefaults, so reinstalling during testing doesn't
//  silently reset the running total back to near-zero. This is a local
//  heuristic only: Apple publishes no per-device lifetime generateKey() count
//  to check it against (appattestkit-module-design.md §8a) — it's just a
//  sanity-check total for whoever is running the checklist, not an
//  authoritative limit, and nothing in AppAttestKit branches on it.
//

import Foundation
import Security

///
/// Two totals, because they are two different things and easy to conflate:
/// `keysGenerated` counts `generateKey()` — local Secure Enclave work, no
/// network — and `appleAttestations` counts successful `attestKey()` calls,
/// the only step in registration that reaches Apple's servers. A flow that
/// fails at /challenge spends a key but never an attestation.
struct RealAttemptCounter {
    /// Keeps the original Keychain account name so totals from earlier
    /// installs carry over.
    static let keysGenerated = RealAttemptCounter(account: "realAttemptCount")
    static let appleAttestations = RealAttemptCounter(account: "appleAttestationCount")

    private static let service = "com.securechat.appattesttestapp.counters"
    private let account: String

    func load() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              let value = Int(string) else {
            return 0
        }
        return value
    }

    func increment() {
        let newValue = load() + 1
        let data = Data(String(newValue).utf8)

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

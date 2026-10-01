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

enum RealAttemptCounter {
    private static let service = "com.securechat.appattesttestapp.counters"
    private static let account = "realAttemptCount"

    static func load() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
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

    static func increment() {
        let newValue = load() + 1
        let data = Data(String(newValue).utf8)

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
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }
}

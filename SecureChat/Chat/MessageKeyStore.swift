//
//  MessageKeyStore.swift
//  SecureChat
//
//  One key per contact for the messages stored with them (storage option B,
//  session-workflow.md, "Message storage"). The text of every message is
//  sealed with its contact's key before it reaches the database, so
//  deleting the key makes whatever is left on disk (rows, journals, free
//  pages, worn flash) unreadable: crypto-shredding
//  (architecture-decisions.md, "Local storage").
//
//  Keys are Keychain items available only while the phone is unlocked and
//  never restored to another device.
//

import Foundation
import CryptoKit
import Security

struct MessageKeyStore {

    private let read: (UUID) throws -> Data?
    private let write: (UUID, Data) throws -> Void
    private let remove: (UUID) throws -> Void
    private let stored: () throws -> [UUID]

    /// The Keychain items every build that ships uses.
    static let live = MessageKeyStore(keychainService: "chat.securechat.messagekeys")

    /// Keychain-backed. Tests pass a throwaway service.
    init(keychainService service: String) {
        read = { try MessageKeychain.read(service: service, peer: $0) }
        write = { try MessageKeychain.write($1, service: service, peer: $0) }
        remove = { try MessageKeychain.delete(service: service, peer: $0) }
        stored = { try MessageKeychain.peers(service: service) }
    }

#if DEBUG
    /// Tests only: lives as long as the value and touches nothing.
    /// `onRead` sees every read, which on a phone is a Keychain round trip.
    static func inMemory(onRead: @escaping (UUID) -> Void = { _ in }) -> MessageKeyStore {
        final class Box { var keys: [UUID: Data] = [:] }
        let box = Box()
        return MessageKeyStore(read: { onRead($0); return box.keys[$0] }, write: { box.keys[$0] = $1 },
                               remove: { box.keys[$0] = nil }, stored: { Array(box.keys.keys) })
    }
#endif

    private init(read: @escaping (UUID) throws -> Data?, write: @escaping (UUID, Data) throws -> Void,
                 remove: @escaping (UUID) throws -> Void, stored: @escaping () throws -> [UUID]) {
        self.read = read
        self.write = write
        self.remove = remove
        self.stored = stored
    }

    /// The contact's key, created on first use.
    func key(for peer: UUID) throws -> SymmetricKey {
        if let existing = try existingKey(for: peer) { return existing }
        let key = SymmetricKey(size: .bits256)
        try write(peer, key.withUnsafeBytes { Data($0) })
        return key
    }

    /// Never creates one: a missing key means those messages are gone.
    func existingKey(for peer: UUID) throws -> SymmetricKey? {
        try read(peer).map { SymmetricKey(data: $0) }
    }

    func delete(for peer: UUID) throws {
        try remove(peer)
    }

    /// Removes the keys of everyone not in `keep`: after a reinstall the
    /// Keychain outlives the database, and nothing would ever use them.
    func deleteAll(except keep: Set<UUID>) throws {
        for peer in try stored() where !keep.contains(peer) {
            try remove(peer)
        }
    }
}

/// Sealing one message's text. Only the text: who, when and the status stay
/// readable in the database (a known limit, session-workflow.md).
enum MessageSeal {

    static func seal(_ text: String, id: UUID, peer: UUID, key: SymmetricKey) throws -> Data {
        try ChaChaPoly.seal(Data(text.utf8), using: key, authenticating: binding(id: id, peer: peer)).combined
    }

    /// Fails for a wrong key, a changed byte, or a row moved to another
    /// message or contact.
    static func open(_ sealed: Data, id: UUID, peer: UUID, key: SymmetricKey) throws -> String {
        let box = try ChaChaPoly.SealedBox(combined: sealed)
        let data = try ChaChaPoly.open(box, using: key, authenticating: binding(id: id, peer: peer))
        return String(decoding: data, as: UTF8.self)
    }

    /// The ciphertext belongs to this message of this contact.
    private static func binding(id: UUID, peer: UUID) -> Data {
        withUnsafeBytes(of: id.uuid) { Data($0) } + withUnsafeBytes(of: peer.uuid) { Data($0) }
    }
}

private enum MessageKeychain {

    static func read(service: String, peer: UUID) throws -> Data? {
        var query = base(service: service, peer: peer)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw MessageKeyError(status: status)
        }
    }

    static func write(_ data: Data, service: String, peer: UUID) throws {
        var query = base(service: service, peer: peer)
        query[kSecValueData as String] = data
        // As the identity key: only while unlocked, never on another device.
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw MessageKeyError(status: status) }
    }

    static func delete(service: String, peer: UUID) throws {
        let status = SecItemDelete(base(service: service, peer: peer) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw MessageKeyError(status: status) }
    }

    static func peers(service: String) throws -> [UUID] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            let items = result as? [[String: Any]] ?? []
            return items.compactMap { ($0[kSecAttrAccount as String] as? String).flatMap(UUID.init(uuidString:)) }
        case errSecItemNotFound:
            return []
        default:
            throw MessageKeyError(status: status)
        }
    }

    private static func base(service: String, peer: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: peer.uuidString
        ]
    }
}

struct MessageKeyError: Error {
    let status: OSStatus
}

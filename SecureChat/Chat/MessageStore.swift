//
//  MessageStore.swift
//  SecureChat
//
//  The messages of every chat, kept in memory and written through to the
//  database. Callers say "save this text for this contact"; how it is
//  stored stays in here: the text sealed with the contact's key
//  (`MessageKeyStore`, storage option B), so deleting a chat deletes its key
//  first and whatever is left on disk can no longer be read.
//

import Foundation
import CryptoKit

@MainActor @Observable
final class MessageStore {

    private var byPeer: [UUID: [StoredMessage]] = [:]

    @ObservationIgnored private let db: DatabaseStrategy
    @ObservationIgnored private let keys: MessageKeyStore
    /// Each contact's key, read once: a Keychain read per message froze
    /// the first launch over hundreds of messages on a phone.
    @ObservationIgnored private var keyCache: [UUID: SymmetricKey] = [:]

    /// - Parameter keepKeysFor: contacts whose keys must stay. Any other
    ///   key is deleted (a reinstall leaves the Keychain behind).
    init(db: DatabaseStrategy, keys: MessageKeyStore, keepKeysFor contacts: Set<UUID>) {
        self.db = db
        self.keys = keys
        sealPlaintextMessages()
        do {
            let rows = try db.fetchMessages()
            byPeer = Dictionary(grouping: rows.map(open), by: \.peer)
            try keys.deleteAll(except: contacts.union(byPeer.keys))
        } catch {
            SCLogger.logger.error(message: "Could not read messages", error: error, category: .Database)
        }
    }

    /// Oldest first.
    func messages(with peer: UUID) -> [StoredMessage] {
        byPeer[peer] ?? []
    }

    func add(_ message: StoredMessage) {
        do {
            try db.addMessage(try seal(message))
        } catch {
            // Still shown: losing it from the screen too would hide that it
            // was written or received at all.
            SCLogger.logger.error(message: "Could not save a message", error: error, category: .Database)
        }
        byPeer[message.peer, default: []].append(message)
    }

    /// Our messages to `peer` still waiting for the session to open.
    func resolveWaiting(with peer: UUID, as status: StoredMessage.Status) {
        guard let messages = byPeer[peer] else { return }
        let ids = messages.filter { $0.status == .waiting }.map(\.id)
        guard !ids.isEmpty else { return }
        do {
            try db.updateStatus(of: ids, to: status)
        } catch {
            SCLogger.logger.error(message: "Could not update message status", error: error, category: .Database)
        }
        byPeer[peer] = messages.map { message in
            var message = message
            if message.status == .waiting { message.status = status }
            return message
        }
    }

    /// The connection dropped: whatever was waiting will never go out.
    func resolveAllWaiting(as status: StoredMessage.Status) {
        for peer in byPeer.keys { resolveWaiting(with: peer, as: status) }
    }

    /// Deletes the chat's messages, the key FIRST: once it is gone, any copy
    /// left behind (a journal, a free page, worn flash) cannot be read.
    /// The contact stays; a next message gets a new key.
    func deleteMessages(with peer: UUID) throws {
        try keys.delete(for: peer)
        keyCache[peer] = nil
        byPeer[peer] = nil
        try db.deleteMessages(with: peer)
    }

    // MARK: Sealing

    private func key(for peer: UUID) throws -> SymmetricKey {
        if let cached = keyCache[peer] { return cached }
        let key = try keys.key(for: peer)
        keyCache[peer] = key
        return key
    }

    /// Nil when the contact has no key: their stored messages are gone.
    private func existingKey(for peer: UUID) throws -> SymmetricKey? {
        if let cached = keyCache[peer] { return cached }
        let key = try keys.existingKey(for: peer)
        keyCache[peer] = key
        return key
    }

    private func seal(_ message: StoredMessage) throws -> SealedMessage {
        let key = try key(for: message.peer)
        return SealedMessage(id: message.id, peer: message.peer,
                             sealedText: try MessageSeal.seal(message.text, id: message.id, peer: message.peer, key: key),
                             date: message.date, status: message.status)
    }

    private func open(_ row: SealedMessage) -> StoredMessage {
        var text = StoredMessage.unreadableText
        do {
            if let key = try existingKey(for: row.peer) {
                text = try MessageSeal.open(row.sealedText, id: row.id, peer: row.peer, key: key)
            }
        } catch {
            SCLogger.logger.error(message: "A stored message could not be opened", category: .Database)
        }
        return StoredMessage(id: row.id, peer: row.peer, text: text, date: row.date, status: row.status)
    }

    /// Builds before storage option B wrote plain text: seal it, then drop
    /// the old table and rewrite the file. If sealing fails the plain rows
    /// stay put for the next launch rather than being lost.
    private func sealPlaintextMessages() {
        do {
            let plaintext = try db.plaintextMessages()
            guard !plaintext.isEmpty else {
                try db.dropPlaintextMessages()
                return
            }
            // A run that stopped halfway has sealed some already.
            let sealed = Set(try db.fetchMessages().map(\.id))
            try db.addMessages(plaintext.filter { !sealed.contains($0.id) }.map(seal))
            try db.dropPlaintextMessages()
            SCLogger.logger.info(message: "Sealed \(plaintext.count) plain-text messages", category: .Database)
        } catch {
            SCLogger.logger.error(message: "Could not seal plain-text messages", error: error, category: .Database)
        }
    }
}

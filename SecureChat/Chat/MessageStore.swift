//
//  MessageStore.swift
//  SecureChat
//
//  The messages of every chat, kept in memory and written through to the
//  database. Callers say "save this text for this contact"; how it is
//  stored (plain now, encrypted per contact next) stays in here.
//

import Foundation

@MainActor @Observable
final class MessageStore {

    private var byPeer: [UUID: [StoredMessage]] = [:]

    @ObservationIgnored private let db: DatabaseStrategy

    init(db: DatabaseStrategy) {
        self.db = db
        do {
            byPeer = Dictionary(grouping: try db.fetchMessages(), by: \.peer)
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
            try db.addMessage(message)
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
}

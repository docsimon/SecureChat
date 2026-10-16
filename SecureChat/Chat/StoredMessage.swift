//
//  StoredMessage.swift
//  SecureChat
//
//  One message in a chat with a contact.
//

import Foundation

struct StoredMessage: Identifiable, Equatable {

    enum Status: Int {
        /// From the contact.
        case received = 0
        /// Ours, written before the session was open; it goes out when it opens.
        case waiting = 1
        /// Ours, handed to the relay. Not a delivery receipt: there are none
        /// yet (session-workflow.md, "Known limits").
        case sent = 2
        /// Ours, and it never left: the contact was offline, did not answer,
        /// or the connection dropped first. Nothing is kept for later (§1).
        case notDelivered = 3
    }

    let id: UUID
    /// The contact's account id.
    let peer: UUID
    let text: String
    let date: Date
    var status: Status

    var isMine: Bool { status != .received }

    /// Shown for a stored message whose key is gone or whose bytes changed.
    static let unreadableText = "This message can't be read."

    init(id: UUID = UUID(), peer: UUID, text: String, date: Date = Date(), status: Status) {
        self.id = id
        self.peer = peer
        self.text = text
        self.date = date
        self.status = status
    }
}

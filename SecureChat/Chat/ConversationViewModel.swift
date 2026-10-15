//
//  ConversationViewModel.swift
//  SecureChat
//
//  The chat with one contact: its messages, the state of the session, and
//  sending. Opening the chat opens the session.
//

import Foundation
import PairingKit
import SessionKit

@MainActor @Observable
final class ConversationViewModel {

    /// What the line under the title says.
    enum Status: Equatable {
        case connecting
        case starting
        case open
        case offline
        case unanswered
        case ended
        /// Connected, nothing tried yet.
        case idle
    }

    let contact: PairedContact
    var draft = ""

    @ObservationIgnored private let connection: RelayConnection
    @ObservationIgnored private let store: MessageStore

    init(contact: PairedContact, connection: RelayConnection, store: MessageStore) {
        self.contact = contact
        self.connection = connection
        self.store = store
    }

    var messages: [StoredMessage] { store.messages(with: contact.accountUUID) }

    var status: Status {
        guard connection.state == .connected else { return .connecting }
        switch connection.peerStatus[contact.accountUUID] {
        case .starting: return .starting
        case .open: return .open
        case .offline: return .offline
        case .unanswered: return .unanswered
        case .ended: return .ended
        case nil: return .idle
        }
    }

    var statusText: String {
        switch status {
        case .connecting: return "Connecting…"
        case .starting: return "Starting a secure session…"
        case .open: return "Secure session"
        case .offline: return "\(contact.displayName) is offline. Messages aren't kept for later."
        case .unanswered: return "\(contact.displayName) didn't answer."
        case .ended: return "The session ended. Your next message starts a new one."
        case .idle: return ""
        }
    }

    /// Too long for one message: there is no splitting yet.
    var draftIsTooLong: Bool {
        draft.utf8.count > SessionContent.maxContentBytes
    }

    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !draftIsTooLong
            && connection.state == .connected
    }

    func appeared() {
        connection.chatOpened(with: contact.accountUUID)
    }

    func disappeared() {
        connection.chatClosed(with: contact.accountUUID)
    }

    func send() {
        guard canSend else { return }
        let text = draft
        draft = ""
        connection.send(text, to: contact.accountUUID)
    }
}

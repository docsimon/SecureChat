//
//  Factories.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//
import Foundation

protocol ChatFactoryProtocol {
    func make(id: UUID, title: String, guests: [Guest], messages: [Message], date: Date) -> Chat
}

protocol GuestFactoryProtocol {
    func make(id: UUID, username: String) -> Guest
}

protocol MessageFactoryProtocol {
    func make(id: UUID, chatID: UUID, guestID: UUID, content: String, date: Date, ttl: Int) -> Message
}

final class ChatFactory: ChatFactoryProtocol {

    static let shared = ChatFactory()
    
    func make(id: UUID = UUID(), title: String, guests: [Guest], messages: [Message], date: Date) -> Chat {
        return Chat(id: id, title: title, guests: guests, messages: messages, date: date)
    }
}

final class GuestFactory: GuestFactoryProtocol {
    static let shared = GuestFactory()
    
    func make(id: UUID, username: String) -> Guest {
        return Guest(id: id, username: username)
    }
}

final class MessageFactory: MessageFactoryProtocol {
    static let shared = MessageFactory()
    
    func make(id: UUID, chatID: UUID, guestID: UUID, content: String,  date: Date, ttl: Int) -> Message {
        return Message(id: id, chatID: chatID, guestID: guestID, content: content, date: date, ttl: ttl)
    }
}

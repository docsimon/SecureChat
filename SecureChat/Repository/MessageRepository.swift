//
//  MessageRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 05/10/2025.
//

import Foundation
import SQLite

protocol MessageRepositoryProtocol {
    func getMessage(with id: MessageID) -> Message?
    func createMessage(with text: String, chatID: ChatID) -> Message
    func saveMessage(message: Message)
}

final class MessageRepository: MessageRepositoryProtocol {
    
    //static let shared = MessageRepository()
    
    private let db: DatabaseStrategy
    
    init(db: DatabaseStrategy) {
        self.db = db
    }
    
    func getMessage(with id: MessageID) -> Message? {
        return db.getMessage(id: id)
    }
    
    func createMessage(with text: String, chatID: ChatID) -> Message {
        do {
            let sender = try db.getOwner()
            let message = Message(id: UUID(), chatID: chatID, guestID: sender, content: text, date: Date(), ttl: 10)
            return message
             
        } catch {
            SCLogger.logger.error(message: "Error creating the message", error: error, category: .Message)
            fatalError()
        }
    }

    func saveMessage(message: Message) {
        db.saveMessage(message: message)
    }
}

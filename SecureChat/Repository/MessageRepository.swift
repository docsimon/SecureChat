//
//  MessageRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 05/10/2025.
//

import Foundation

protocol MessageRepositoryProtocol {
    func getMessage(with id: MessageID) -> Message?
    func createMessage(with text: String, chatID: ChatID)
}

final class MessageRepository: MessageRepositoryProtocol {
    
    private let db: DatabaseStrategy
    
    init(db: DatabaseStrategy = CustomDB.shared) {
        self.db = db
    }
    
    func getMessage(with id: MessageID) -> Message? {
        return db.getMessage(id: id)
    }
    
    func createMessage(with text: String, chatID: ChatID)  {
        let message = Message(id: MessageID(id: UUID()), chatID: chatID, guestID: GlobalState.userID, content: text, date: Date(), ttl: 10)
        db.saveMessage(message: message)
    }

}

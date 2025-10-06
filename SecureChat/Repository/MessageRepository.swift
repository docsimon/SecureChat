//
//  MessageRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 05/10/2025.
//

import Foundation

protocol MessageRepositoryProtocol {
    func getMessage(with id: MessageID) -> Message?
}

final class MessageRepository: MessageRepositoryProtocol {
    
    private let db: DatabaseStrategy
    
    init(db: DatabaseStrategy = CustomDB()) {
        self.db = db
    }
    
    func getMessage(with id: MessageID) -> Message? {
        return db.getMessage(id: id)
    }

}

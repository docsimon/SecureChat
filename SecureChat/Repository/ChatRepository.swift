//
//  ChatRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol ChatRepositoryProtocol {
    var chatList: [ChatListModel] { get }
    func getMessage(from id: MessageID) -> Message
    func getChat(with id: ChatID) -> Chat?
}

final class ChatRepository: ChatRepositoryProtocol {

    let guestRepo: GuestRepositoryProtocol
    let messageRepo: MessageRepositoryProtocol
    let db: DatabaseStrategy
    
    
    init(guestRepo: GuestRepositoryProtocol = GuestRepository(), messageRepo: MessageRepositoryProtocol = MessageRepository(), db: DatabaseStrategy = CustomDB()) {
        self.guestRepo = guestRepo
        self.messageRepo = messageRepo
        self.db = db
    }
    

    var chatList: [ChatListModel] {
        db.chatList
    }
    
    func getMessage(from id: MessageID) -> Message {
        guard let message = messageRepo.getMessage(with: id) else {
            fatalError("Message cannot be nil")
        }
        return message
    }
    
    func getChat(with id: ChatID) -> Chat? {
        return db.getChat(id: id)
    }
    
}

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
    //func sendMessage(message: Message) async
    func createMessage(with text: String, chatID: ChatID) async
}

final class ChatRepository: ChatRepositoryProtocol, DatabaseDelegate {
    
    let guestRepo: GuestRepositoryProtocol
    let messageRepo: MessageRepositoryProtocol
    private var db: DatabaseStrategy
    
    
    init(guestRepo: GuestRepositoryProtocol = GuestRepository(), messageRepo: MessageRepositoryProtocol = MessageRepository(), db: DatabaseStrategy = CustomDB.shared) {
        self.guestRepo = guestRepo
        self.messageRepo = messageRepo
        self.db = db
        self.db.delegate = self
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
    
    func createMessage(with text: String, chatID: ChatID) {
        messageRepo.createMessage(with: text, chatID: chatID)
    }
    
    //MARK: DatabaseDelegate
    
    func messageUpdated(message: Message) {
        // logic to send the message
        
        // logic to update the chat view
        print("There is a new message", message.content)
    }
    
    private func sendMessage(message: Message) async {

    }
   
}

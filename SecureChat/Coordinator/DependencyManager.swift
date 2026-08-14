//
// DependencyManager.swift
// SecureChat
//
// Created by Simone Barbara on 08/10/2025.                               
// All Rights Reserved.

import Foundation

final class DependencyManager {
    
    let chatRepo: ChatRepositoryProtocol
    let guestRepo: GuestRepositoryProtocol
    let messageRepo: MessageRepositoryProtocol
    private var db: DatabaseStrategy
    let client: ClientProtocol

    init() {
        do {
            self.db = try SQLiteDB()
            SCLogger.logger.info(message: LogMessage.SQLiteDBCreated, category: .Database)
        } catch {
            self.db = CustomDB()
            SCLogger.logger.error(message: LogMessage.SQLiteDBNotCreated, error: error, category: .Database)
        }
        
        let notificationCenter = NotificationCenter.default
        client = WebsocketClient()
        let adapter = JSONAdapterImpl()
        
        // GuestRepository
        guestRepo = GuestRepository(db: db)
        
        
        /* ************************** */
        /* USE ONLY FOR TESTING USERS */
//        #if DEBUG
//        guestRepo.addGuest(username: "Sempronio", id: nil)
//        #endif
        /* ************************** */
        
        // MessageRepository
        messageRepo = MessageRepository(db: db)
        // ChatRepository
        chatRepo = ChatRepository(guestRepo: guestRepo, messageRepo: messageRepo, db: db, notificationCenter: notificationCenter, client: client, adapter: adapter)
    }
    
    func makeChatListViewModel() -> ChatListViewModel {
        return ChatListViewModel(chatRepo: chatRepo)
    }
    
    func makeChatViewModel(with id: ChatID) -> ChatViewModel {
        return ChatViewModel(repository: chatRepo, chatID: id)
    }
    
    func makeMessageViewModel(for message: Message) -> MessageViewModel {
        return MessageViewModel(message: message, guestRepo: guestRepo)
    }
    
    func makeMessageViewModel(from id: MessageID) -> MessageViewModel {
        let message = chatRepo.getMessage(from: id)
        return MessageViewModel(message: message, guestRepo: guestRepo)
    }
}

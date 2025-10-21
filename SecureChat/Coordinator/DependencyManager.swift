//
// DependencyManager.swift
// SecureChat
//
// Created by Simone Barbara on 08/10/2025.                               
// All Rights Reserved.

import Foundation

final class DependencyManager {
    
    static let shared = DependencyManager()
    
    let chatRepo: ChatRepositoryProtocol
    let guestRepo: GuestRepositoryProtocol
    let messageRepo: MessageRepositoryProtocol
    private var db: DatabaseStrategy
    let client: ClientProtocol

    init() {
        do {
            self.db = try SQLiteDB()
        } catch {
            self.db = CustomDB()
            SCLogger.logger.error(message: LogMessage.SQLiteDBNotCreated, error: error, category: .Database)
        }
        
        let session = URLSession.shared
        let notificationCenter = NotificationCenter.default
        SCLogger.logger.info(message: LogMessage.SQLiteDBCreated, category: .Database)
        client = WebsocketClient(session: session)
        let adapter = JSONAdapter()
        
        // GuestRepository
        guestRepo = GuestRepository(db: db)
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

//
// DependencyManager.swift
// SecureChat
//
// Created by Simone Barbara on 08/10/2025.                               
// All Rights Reserved.

import Foundation

final class DependencyManager {
    
    let chatRepo: ChatRepositoryProtocol
    let guestRepo: GuestRepository
    let messageRepo: MessageRepositoryProtocol
    private var db: DatabaseStrategy
    let client: ClientProtocol
    let authService: AuthService
    let networkAdapter: NetworkAdapter
    let jsonAdapter: JSONAdapter
    let registrationRepo: RegistrationRepository

    init() {
        do {
            self.db = try SQLiteDB()
            SCLogger.logger.info(message: LogMessage.SQLiteDBCreated, category: .Database)
        } catch {
            SCLogger.logger.error(message: LogMessage.SQLiteDBNotCreated, error: error, category: .Database)
            fatalError()
        }
        
        let notificationCenter = NotificationCenter.default
        client = WebsocketClient()
        let adapter = JSONAdapterImpl()
        
        // GuestRepository
        guestRepo = GuestRepositoryImpl(db: db)
        
        
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
        // JSONAdapter
        jsonAdapter = JSONAdapterImpl()
        // NetworkAdapter
        networkAdapter = NetworkAdapterImpl(session: URLSession.shared)
        // AuthService
        authService = AuthServiceImpl(networkAdapter: networkAdapter, jsonAdapter: jsonAdapter, baseAddress: .baseAddressAuth)
        // Registration repository
        registrationRepo = RegistrationRepositoryImpl(db: db)
        
    }
    
    @MainActor func makeChatListViewModel() -> ChatListViewModel {
        return ChatListViewModel(chatRepo: chatRepo)
    }
    
    @MainActor func makeChatViewModel(with id: ChatID) -> ChatViewModel {
        return ChatViewModel(repository: chatRepo, chatID: id)
    }
    
    @MainActor func makeMessageViewModel(for message: Message) -> MessageViewModel {
        return MessageViewModel(message: message, guestRepo: guestRepo)
    }
    
    @MainActor func makeMessageViewModel(from id: MessageID) -> MessageViewModel {
        let message = chatRepo.getMessage(from: id)
        return MessageViewModel(message: message, guestRepo: guestRepo)
    }
    
    @MainActor func makePhoneNumberViewModel() -> PhoneNumberViewModel {
        return PhoneNumberViewModel(authService: authService)
    }
    
    @MainActor func makeRegistrationRouterViewModel() -> RegistrationRouterViewModel {
        return RegistrationRouterViewModel(registrationRepo: registrationRepo, guestRepo: guestRepo)
    }
    
}

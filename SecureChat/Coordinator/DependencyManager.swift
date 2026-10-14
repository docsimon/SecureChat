//
// DependencyManager.swift
// SecureChat
//
// Created by Simone Barbara on 08/10/2025.                               
// All Rights Reserved.

import Foundation
import AppAttestKit
import RegistrationKit

@MainActor
final class DependencyManager {
    
    let chatRepo: ChatRepositoryProtocol
    let guestRepo: GuestRepository
    let messageRepo: MessageRepositoryProtocol
    private var db: DatabaseStrategy
    let client: ClientProtocol
    let networkAdapter: NetworkAdapter
    let jsonAdapter: JSONAdapter
    /// One per process: it owns the App Attest state machine, and two of
    /// them would write the same Keychain state.
    let attestationCoordinator: AttestationCoordinator
    let registrationViewModel: RegistrationViewModel
    let contactRepo: ContactRepository
    private var identityProvider = LocalIdentityProvider()
    lazy var ownerID: UUID =  {
        do {
            return try guestRepo.getOwner().id
        } catch {
            SCLogger.logger.error(message: "Owner not found. This is a blocking error", error: error, category: .Database)
            fatalError()
        }
    }()
    
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
        // Registration
        var transport: AttestationTransport = RealAttestationTransport(baseURL: AuthServerEnvironment.baseURL)
#if DEBUG
        transport = EnvironmentLoggingTransport(base: transport)
#endif
        attestationCoordinator = AttestationCoordinator(transport: transport, observer: RegistrationLogObserver())
        registrationViewModel = RegistrationViewModel(coordinator: attestationCoordinator)
#if DEBUG
        // Debug builds skip registration, so running the app never spends an
        // App Attest key. The real flow (development App Attest + the local
        // Auth Server) runs only from the "SecureChat Real Registration"
        // scheme, which passes the launch argument `-RealRegistration YES`.
        registrationViewModel.assumesRegistered = !UserDefaults.standard.bool(forKey: "RealRegistration")
        // A run that skipped registration has no identity to pair with.
        identityProvider.usesDebugIdentity = registrationViewModel.assumesRegistered
#endif
        // Pairing
        contactRepo = ContactRepository(db: db)
    }
    
    @MainActor func makeChatListViewModel() -> ChatListViewModel {
        return ChatListViewModel(chatRepo: chatRepo)
    }
    
    @MainActor func makePairingViewModel() -> PairingViewModel {
        return PairingViewModel(identity: identityProvider.load, contacts: contactRepo)
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
    
}

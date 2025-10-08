//
//  ChatViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI
import Observation

protocol ChatViewModelProtocol {
    var chat: Chat? { get set }
    func getMessage(from id: MessageID) -> Message
    func createMessage(with text: String) async
}

@Observable
final class ChatViewModel: ChatViewModelProtocol, ChatRepositoryDelegate {

    let chatID: UUID
    let repo: ChatRepositoryProtocol
    private var newChat: Chat?
    
    init(repository: ChatRepositoryProtocol = ChatRepository.shared, chatID: ChatID) {
        self.chatID = chatID
        self.repo = repository
        self.repo.delegate = self
        newChat = repo.getChat(with: chatID)
    }
    
    var chat: Chat? {
        get {
            newChat
        }
        set {
            newChat = newValue
        }
    }
    
    func getMessage(from id: MessageID) -> Message {
        return repo.getMessage(from: id)
    }
    
    func createMessage(with text: String) async {
        print("Message sent!", text)
        await repo.createMessage(with: text, chatID: chatID)
    }
    
    //MARK: ChatRepositoryDelegate
    
    func messageUpdated(message: Message) {
        // logic to send the message
        
        // logic to update the chat view
        print("There is a new message")
        newChat = repo.getChat(with: chatID)
    }
}

//
//  ChatViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI


protocol ChatViewModelProtocol {
    var chat: Chat? { get }
    func getMessage(from id: MessageID) -> Message
    //func sendMessage(text: String) async
}

@Observable
final class ChatViewModel: ChatViewModelProtocol {
    
    let chatID: UUID
    let repo: ChatRepositoryProtocol
    
    init(repository: ChatRepositoryProtocol = ChatRepository(), chatID: ChatID) {
        self.chatID = chatID
        self.repo = repository
    }
    
    var chat: Chat? {
        repo.getChat(with: chatID)
    }
    
    func getMessage(from id: MessageID) -> Message {
        return repo.getMessage(from: id)
    }
    
//    func sendMessage(text: String) async {
//        
//    }
}

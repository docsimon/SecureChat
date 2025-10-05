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
        repo.chat.filter { $0.id == chatID }.first
    }
    
    func getMessage(from id: MessageID) -> Message {
        return repo.getMessage(from: id)
    }
}

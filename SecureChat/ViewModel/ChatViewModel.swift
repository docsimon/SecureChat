//
//  ChatViewModel.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI


protocol ChatViewModelProtocol {
    var chat: Chat? { get }
}

@Observable
final class ChatViewModel: ChatViewModelProtocol {
    
    let chatID: UUID
    let repo: ChatRepositoryProtocol
    
    init(repository: ChatRepositoryProtocol = ChatRepository(), chatID: UUID) {
        self.chatID = chatID
        self.repo = repository
    }
    
    var chat: Chat? {
        repo.chat.filter { $0.id == chatID }.first
    }
}

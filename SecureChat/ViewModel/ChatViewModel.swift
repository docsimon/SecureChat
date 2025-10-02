//
//  ChatViewModel.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI

@Observable

final class ChatViewModel {
    
    let chatID: UUID
    let repo: ChatRepositoryProtocol
    
    init(repository: ChatRepositoryProtocol = ChatRepository(), chatID: UUID) {
        self.chatID = chatID
        self.repo = repository
    }

}

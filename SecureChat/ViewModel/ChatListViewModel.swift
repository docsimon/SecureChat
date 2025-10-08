//
//  ChatListViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI

protocol ChatListViewModelProtocol {
    var chatList: [ChatListModel] { get }
}

@Observable
final class ChatListViewModel: ChatListViewModelProtocol {

    let chatRepo: ChatRepositoryProtocol
    
    init(chatRepo: ChatRepositoryProtocol = ChatRepository.shared) {
        self.chatRepo = chatRepo
    }
    
    var chatList: [ChatListModel] {
        return chatRepo.chatList
    }
}

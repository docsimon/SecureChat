//
//  ChatListViewModel.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI

protocol ChatListViewModelProtocol {
    var chatList: [ChatListModel] { get }
}

@Observable
final class ChatListViewModel: ChatListViewModelProtocol {

    let chatRepo: ChatRepositoryProtocol
    
    init(chatRepo: ChatRepositoryProtocol = ChatRepository()) {
        self.chatRepo = chatRepo
    }
    
    var chatList: [ChatListModel] {
        return chatRepo.chatList
    }
    
    func printID(model: ChatListModel) {
        print(model.chatID)
    }
    
}

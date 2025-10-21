//
//  ChatListViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import SwiftUI

protocol ChatListViewModelProtocol {
    var chatList: [ChatListModel] { get set }
    func createChat(title: String)
}

@Observable
final class ChatListViewModel: ChatListViewModelProtocol {

    let chatRepo: ChatRepositoryProtocol
    
    
    init(chatRepo: ChatRepositoryProtocol) {
        self.chatRepo = chatRepo
        chatList = chatRepo.chatList
    }

    var chatList: [ChatListModel] = []
       
    func createChat(title: String) {
        chatRepo.createChat(title: title)
        chatList = chatRepo.chatList
    }
}

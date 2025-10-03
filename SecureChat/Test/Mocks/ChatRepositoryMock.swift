//
//  Untitled.swift
//  SecureChat
//
//  Created by doc on 03/10/2025.
//

import Foundation

final class ChatRepositoryMock: ChatRepositoryProtocol {
    
    var chatStub = [Chat]()
    var chatListStub = [ChatListModel]()
    
    var chat: [Chat] {
        return chatStub
    }
    
    var chatList: [ChatListModel] {
        return chatListStub
    }
}

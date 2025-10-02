//
//  ChatListViewModel.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI

@Observable

final class ChatListViewModel {
    var chatList: [ChatListModel] = [
        ChatListModel(chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, title: "Chat 1", timestamp: Date.now.description),
        ChatListModel(chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, title: "Chat 2", timestamp: Date.now.description),
        ChatListModel(chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, title: "Chat 3", timestamp: Date.now.description)
    ]
    
    func printID(model: ChatListModel) {
        print(model.chatID)
    }
    
}
/*
578E8708-36DC-4820-86DF-4CB00A1EC8C8
CA654CF5-862E-4FDA-8856-35B67564A07B
73B44F3D-240E-4025-81E3-16B29B6333A7
*/

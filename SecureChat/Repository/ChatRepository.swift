//
//  ChatRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol ChatRepositoryProtocol {
    var chat: [Chat] { get }
    var chatList: [ChatListModel] { get }
    func getMessage(from id: MessageID) -> Message
}

final class ChatRepository: ChatRepositoryProtocol {
    
    let guestRepo: GuestRepositoryProtocol
    let messageRepo: MessageRepositoryProtocol
    
    init(guestRepo: GuestRepositoryProtocol = GuestRepository(), messageRepo: MessageRepositoryProtocol = MessageRepository()) {
        self.guestRepo = guestRepo
        self.messageRepo = messageRepo
    }
    
    var chat: [Chat] {
        // chat 1
        let chatID_1 = UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!
        let chat1 = Chat(id: chatID_1, title: "Chat 1", guests: [guestRepo.guest[0].id, guestRepo.guest[1].id], messages: [MessageID(id: messageRepo.mockMessages[0].id), MessageID(id: messageRepo.mockMessages[1].id)], date: Date.now)
        
        // chat 2
        let chatID_2 = UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!
        let chat2 = Chat(id: chatID_2, title: "Chat 2", guests: [guestRepo.guest[2].id, guestRepo.guest[3].id], messages: [MessageID(id: messageRepo.mockMessages[2].id), MessageID(id: messageRepo.mockMessages[3].id)], date: Date.now)
        
        // chat 2
        let chatID_3 = UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!
        let chat3 = Chat(id: chatID_3, title: "Chat3", guests: [guestRepo.guest[4].id, guestRepo.guest[5].id], messages: [MessageID(id: messageRepo.mockMessages[4].id), MessageID(id: messageRepo.mockMessages[5].id)], date: Date.now)
        
        return [chat1, chat2, chat3]
    }
    
    var chatList: [ChatListModel] = [
        ChatListModel(chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, title: "Chat 1", date: Date.now),
        ChatListModel(chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, title: "Chat 2", date: Date.now),
        ChatListModel(chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, title: "Chat 3", date: Date.now)
    ]
    
    func getMessage(from id: MessageID) -> Message {
        guard let message = messageRepo.getMessage(with: id) else {
            fatalError("Message cannot be nil")
        }
        return message
    }
    
}

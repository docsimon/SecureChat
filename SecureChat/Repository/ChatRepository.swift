//
//  ChatRepository.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import Foundation

protocol ChatRepositoryProtocol {
    var chat: [Chat] { get }
}

final class ChatRepository: ChatRepositoryProtocol {
    let guestRepo = GuestRepository()
    var chat: [Chat] {
        // chat 1
        let chatID_1 = UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8") ?? UUID()
        let guest_1 = guestRepo.guest[0]
        let message_1 = MessageFactory.shared.make(id: UUID(), chatID: chatID_1, guestID: guest_1.id, content: "content of message 1", timestamp: Date().ISO8601Format(), ttl: 10)
        let guest_2 = guestRepo.guest[1]
        let message_2 = MessageFactory.shared.make(id: UUID(), chatID: chatID_1, guestID: guest_2.id, content: "content of message 2", timestamp: Date().ISO8601Format(), ttl: 10)
        let chat1 = Chat(id: chatID_1, title: "Chat 1", guests: [guest_1, guest_2], messages: [message_1, message_2], timestamp: Date.now.description)
        
        // chat 2
        let chatID_2 = UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B") ?? UUID()

        let guest_3 = guestRepo.guest[2]
        let message_3 = MessageFactory.shared.make(id: UUID(), chatID: chatID_2, guestID: guest_3.id, content: "content of message 3", timestamp: Date().ISO8601Format(), ttl: 10)
        let guest_4 = guestRepo.guest[3]
        let message_4 = MessageFactory.shared.make(id: UUID(), chatID: chatID_2, guestID: guest_4.id, content: "content of message 4", timestamp: Date().ISO8601Format(), ttl: 10)
        let chat2 = Chat(id: chatID_2, title: "Chat 2", guests: [guest_3, guest_4], messages: [message_3, message_4], timestamp: Date.now.description)
        
        // chat 2
        let chatID_3 = UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7") ?? UUID()

        let guest_5 = guestRepo.guest[4]
        let message_5 = MessageFactory.shared.make(id: UUID(), chatID: chatID_3, guestID: guest_5.id, content: "content of message 5", timestamp: Date().ISO8601Format(), ttl: 10)
        let guest_6 = guestRepo.guest[5]
        let message_6 = MessageFactory.shared.make(id: UUID(), chatID: chatID_3, guestID: guest_6.id, content: "content of message 6", timestamp: Date().ISO8601Format(), ttl: 10)
        let chat3 = Chat(id: chatID_3, title: "Chat3", guests: [guest_5, guest_6], messages: [message_5, message_6], timestamp: Date.now.description)
        
        return [chat1, chat2, chat3]
    }
}

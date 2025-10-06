//
//  MessageRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 05/10/2025.
//

import Foundation

protocol MessageRepositoryProtocol {
    func getMessage(with id: MessageID) -> Message?
    var mockMessages: [Message] { get }
//    func createMessage(with text: String) -> Message
}

final class MessageRepository: MessageRepositoryProtocol {
    
    func getMessage(with id: MessageID) -> Message? {
        return mockMessages.filter { $0.id == id.id }.first
    }
    
    private var messages: [Message] {
        [
            Message(id: UUID(uuidString: "00000000-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, guestID: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!, content: "content of message 1, ciao come stai?", date: Date(), ttl: 10),
            Message(id: UUID(uuidString: "00000001-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, guestID: UUID(uuidString: "987fcdeb-1234-5678-9012-34567890abcd")!, content: "content of message 2, bene grazie, tu?", date: Date(), ttl: 10),
            Message(id: UUID(uuidString: "00000002-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, guestID: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!, content: "content of message 3", date: Date(), ttl: 10),
            Message(id: UUID(uuidString: "00000003-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, guestID: UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!, content: "content of message 4", date: Date(), ttl: 10),
            Message(id: UUID(uuidString: "00000004-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, guestID: UUID(uuidString: "f47ac10b-58cc-4372-a567-0e02b2c3d479")!, content: "content of message 5", date: Date(), ttl: 10),
            Message(id: UUID(uuidString: "00000005-240E-4025-81E3-16B29B6333A7")!, chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, guestID:  UUID(uuidString: "1b671a64-40d5-491e-99b0-da01ff1f3341")!, content: "content of message 6", date: Date(), ttl: 10)
        ]
    }
    
    var mockMessages: [Message] {
        return messages
    }
    
//    func createMessage(with text: String) -> Message {
//        
//    }
    
}

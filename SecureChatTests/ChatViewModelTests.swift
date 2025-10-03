//
//  ChatViewModelTests.swift
//  SecureChatTests
//
//  Created by doc on 03/10/2025.
//

import XCTest

@testable import SecureChat

final class ChatViewModelTests: XCTestCase {

    let repo = ChatRepositoryMock()
    var sut: ChatViewModel?
    var chat: Chat?
    
    override func setUpWithError() throws {
        let chatID_1 = try XCTUnwrap(UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8"))
        
        let guest_1 = Guest(id: try XCTUnwrap(UUID(uuidString: "578E8708-0000-4820-86DF-4CB00A1EC8C8")) , username: "Simone")
        let message_1 = MessageFactory.shared.make(id: UUID(), chatID: chatID_1, guestID: guest_1.id, content: "content of message 1, ciao come stai?", date: Date(), ttl: 10)
        
        let guest_2 = Guest(id: try XCTUnwrap(UUID(uuidString: "578E8708-1111-4820-86DF-4CB00A1EC8C8")) , username: "Pietro")
        let message_2 = MessageFactory.shared.make(id: UUID(), chatID: chatID_1, guestID: guest_2.id, content: "content of message 2, bene grazie, tu?", date: Date(), ttl: 10)
        
        chat = Chat(id: chatID_1, title: "Chat 1", guests: [guest_1, guest_2], messages: [message_1, message_2], date: Date.now)
        
        repo.chatStub = [try XCTUnwrap(chat)]
    
        sut = ChatViewModel(repository: repo, chatID: chatID_1)
    }
    
    func testChatIsNotNil() throws {
        XCTAssertNotNil(sut?.chat, "Chat should not be nil")
    }
    
    func testChatIsNil() throws {
        let chatID_not_existent = try XCTUnwrap(UUID(uuidString: "578E8708-0000-0000-0000-4CB00A1EC8C8"))
        sut = ChatViewModel(repository: repo, chatID: chatID_not_existent)
        XCTAssertNil(sut?.chat, "Chat should be nil")
    }
    
    func testChatIsCorrect() throws {
        let targetChat = sut?.chat
        XCTAssertEqual(targetChat, chat)
    }

}

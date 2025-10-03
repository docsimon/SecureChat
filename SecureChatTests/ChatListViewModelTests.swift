//
//  ChatListViewModelTests.swift
//  SecureChat
//
//  Created by doc on 03/10/2025.
//

import XCTest
@testable import SecureChat

final class ChatListViewModelTests: XCTestCase {
    
    let repo = ChatRepositoryMock()
    var sut: ChatListViewModel?
    
    override func setUpWithError() throws {
        sut = ChatListViewModel(chatRepo: repo)
    }

    func testChatListSize() throws {
        repo.chatListStub = makeChatList()
        let sut = try XCTUnwrap(sut)
        XCTAssert(sut.chatList.count == 3)
    }
    
    func testChatListChatID() throws {
        repo.chatListStub = makeChatList()
        let sut = try XCTUnwrap(sut)
        XCTAssertEqual(sut.chatList[0].chatID, UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!)
        XCTAssertEqual(sut.chatList[1].chatID, UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!)
        XCTAssertEqual(sut.chatList[2].chatID, UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!)
    }
    
    func testChatListTitle() throws {
        repo.chatListStub = makeChatList()
        let sut = try XCTUnwrap(sut)
        XCTAssertEqual(sut.chatList[0].title, "Chat 1")
        XCTAssertEqual(sut.chatList[1].title, "Chat 2")
        XCTAssertEqual(sut.chatList[2].title, "Chat 3")
    }
    
    func testChatListDate() throws {
        repo.chatListStub = makeChatList()
        let sut = try XCTUnwrap(sut)
        XCTAssertEqual(sut.chatList[0].date, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(sut.chatList[1].date, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(sut.chatList[2].date, Date(timeIntervalSince1970: 300))
    }
    
    private func makeChatList() -> [ChatListModel] {
        return [ChatListModel(chatID: UUID(uuidString: "578E8708-36DC-4820-86DF-4CB00A1EC8C8")!, title: "Chat 1", date: Date(timeIntervalSince1970: 100)),
                ChatListModel(chatID: UUID(uuidString: "CA654CF5-862E-4FDA-8856-35B67564A07B")!, title: "Chat 2", date: Date(timeIntervalSince1970: 200)),
        ChatListModel(chatID: UUID(uuidString: "73B44F3D-240E-4025-81E3-16B29B6333A7")!, title: "Chat 3", date: Date(timeIntervalSince1970: 300))]
    }

}

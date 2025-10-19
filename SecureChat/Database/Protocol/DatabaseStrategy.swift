//
//  DatabaseStrategy.swift
//  SecureChat
//
//  Created by doc on 06/10/2025.
//

import Foundation

protocol DatabaseStrategy {
    func saveChat(chat: Chat)
    func saveGuest(guest: Guest)
    func saveMessage(message: Message)
    func getMessage(id: MessageID) -> Message?
    func getGuest(id: GuestID) -> Guest?
    func getChat(id: ChatID) -> Chat?
    var chatList: [ChatListModel] { get }
    func bootstrap() throws
}

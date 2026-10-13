//
//  DatabaseStrategy.swift
//  SecureChat
//
//  Created by doc on 06/10/2025.
//

import Foundation
import PairingKit

protocol DatabaseStrategy {
    func saveChat(chat: Chat)
    func addGuest(guest: Guest)
    func update(guest: Guest)
    func saveMessage(message: Message)
    func getMessage(id: MessageID) -> Message?
    func getGuest(id: GuestID) throws -> Guest
    func getChat(id: ChatID) -> Chat?
    var chatList: [ChatListModel] { get }
    func bootstrap() throws
    func createChat(title: String)
    func getOwner() throws -> Guest
    func fetchContacts() throws -> [PairedContact]
    func addContact(_ contact: PairedContact) throws
}

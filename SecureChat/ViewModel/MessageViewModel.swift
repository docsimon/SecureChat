//
//  MessageViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol MessageViewModelProtocol {
    var content: String { get }
    var time: String { get }
    var guestUsername: String { get }
    var isOwner: Bool { get }
    func create(content: String) -> Message?
}

final class MessageViewModel: MessageViewModelProtocol {
    
    var isOwner: Bool {
        return message.isOwner
    }
    
    func create(content: String) -> Message? {
        nil
    }
    
    var content: String {
        message.content
    }

    var time: String {
        getTime(from: message.date)
    }
    
    var guestUsername: String {
        guard let guest = try? getGuest(with: message.guestID) else {
            SCLogger.logger.error(message: "Guest id \(message.guestID) not found", category: .Database)
            fatalError("Cannot receive a message from unknown guests")
            
        }
        print("****** Guest id from the message in the chat", message.guestID)
        print("****** Guest fetched from the message in the chat", guest.id, guest.username)
        return guest.username
    }
    
   
    
    let message: Message
    let guestRepo: GuestRepositoryProtocol
    
    init(message: Message, guestRepo: GuestRepositoryProtocol) {
        self.message = message
        self.guestRepo = guestRepo
    }
    
    private func getTime(from date: Date) -> String {
        let hours = date.formatted(
            Date.FormatStyle()
                .hour(.defaultDigits(amPM: .abbreviated))
                .minute(.twoDigits)
        )
        return hours
    }
    
    private func getGuest(with id: UUID) throws -> Guest {
        try guestRepo.getGuest(id: id)
    }
    
}

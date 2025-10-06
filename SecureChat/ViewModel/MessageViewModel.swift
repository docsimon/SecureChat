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
    var guest: String { get }
    func create(content: String) -> Message?
}

final class MessageViewModel: MessageViewModelProtocol {
    func create(content: String) -> Message? {
        nil
    }
    
    var content: String {
        message.content
    }

    var time: String {
        getTime(from: message.date)
    }
    
    var guest: String {
        let guest = getGuest(with: message.guestID)
        return guest?.username ?? "Unknown"
    }
    
    let message: Message
    let guestRepo: GuestRepositoryProtocol
    
    init(message: Message, guestRepo: GuestRepositoryProtocol = GuestRepository()) {
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
    
    private func getGuest(with id: UUID) -> Guest? {
        guestRepo.getGuest(id: id)
    }
    
}

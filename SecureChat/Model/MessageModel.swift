//
//  MessageModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 01/10/2025.
//

import Foundation

struct Message: Identifiable, Equatable, Codable {
    let id: UUID // Unique identifier of the message
    let chatID: UUID // ID of the chat wher ethe mesage should be diplayed
    let guestID: UUID // The ID of the user creating the message
    let content: String // This is the payload of the message
    let date: Date // The timestamp of the creation of the message
    let ttl: Int // Number of seconds before autodeletion. Negative number means no expiration. This applies to port the parties. If guest A send a message with ttl 1 min, that message will be deleted on both guests when it expires
}

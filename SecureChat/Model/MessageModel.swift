//
//  MessageModel.swift
//  SecureChat
//
//  Created by doc on 01/10/2025.
//

import Foundation

struct Message: Identifiable, Codable {
    let id: UUID // Unique identifier of the message
    let chatID: UUID // ID of the chat wher ethe mesage should be diplayed
    let guestID: UUID // The ID of the user creating the message
    let content: String // This is the payload of the message
    let date: Date // The timestamp when the sender sent the message
    let ttl: Int // Number of seconds before autodeletion. Negative number means no expiration. This applies to port the parties. If guest A send a message with ttl 1 min, that message will be deleted on both guests when it expires
}

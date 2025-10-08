//
//  ChatModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 01/10/2025.
//

import Foundation

typealias GuestID = UUID

struct MessageID: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
}

struct Chat: Equatable {
    let id: UUID
    let title: String
    var guests: [GuestID]
    var messages: [MessageID]
    let date: Date
}

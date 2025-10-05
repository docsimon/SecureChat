//
//  ChatModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 01/10/2025.
//

import Foundation

typealias GuestID = UUID

struct MessageID: Identifiable, Equatable {
    let id: UUID
}

struct Chat: Equatable {
    let id: UUID
    let title: String
    let guests: [GuestID]
    let messages: [MessageID]
    let date: Date
}

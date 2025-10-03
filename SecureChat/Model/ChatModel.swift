//
//  ChatModel.swift
//  SecureChat
//
//  Created by doc on 01/10/2025.
//

import Foundation

struct Chat {
    let id: UUID
    let title: String
    let guests: [Guest]
    let messages: [Message]
    let date: Date
}

//
//  ChatListModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

typealias ChatID = UUID

struct ChatListModel: Identifiable {
    let id = UUID()
    let chatID: ChatID
    let title: String
    let date: Date
    
    var formattedDate: String {
        return date.formatted(
            Date.FormatStyle()
                .year(.defaultDigits)
                .month(.abbreviated)
                .day(.twoDigits)
            )
    }
}

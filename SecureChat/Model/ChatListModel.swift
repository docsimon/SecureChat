//
//  ChatListModel.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import Foundation

struct ChatListModel: Identifiable {
    let id = UUID()
    let chatID: UUID
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

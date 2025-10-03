//
//  ChatListRow.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import SwiftUI

struct ChatListRow: View {
    
    let chatListModel: ChatListModel
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(chatListModel.title)
            Text(chatListModel.formattedDate)
        }
    }
    
}

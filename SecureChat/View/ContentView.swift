//
//  ContentView.swift
//  SecureChat
//
//  Created by doc on 01/10/2025.
//

import SwiftUI

struct ContentView: View {
    @State var chatListViewModel = ChatListViewModel()
    
    var body: some View {
        NavigationStack {
            List(chatListViewModel.chatList) { model in
                NavigationLink {
                    ChatView(viewModel: ChatViewModel(chatID: model.chatID))
                } label: {
                    ChatListRow(chatListModel: model)
                }
            }
            .navigationTitle("Chats")
        }
    }
}

#Preview {
    ContentView()
}

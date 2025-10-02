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
                ChatListRow(chatListModel: model)
            }
        }
    }
}

#Preview {
    ContentView()
}

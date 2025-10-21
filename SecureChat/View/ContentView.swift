//
//  ContentView.swift
//  SecureChat
//
//  Created by Simone Barbara on 01/10/2025.
//

import SwiftUI

struct ContentView: View {
    
    @State var chatListViewModel: ChatListViewModelProtocol
    @State var dep: DependencyManager
    
    var body: some View {
        NavigationStack {
            List(chatListViewModel.chatList) { model in
                NavigationLink(value: model.chatID) {
                    ChatListRow(chatListModel: model)
                        .onAppear {
                            print("chat id:", model.chatID)
                        }
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: UUID.self) { chatID in
                ChatView(viewModel: dep.makeChatViewModel(with: chatID), dep: dep)
                    .onAppear {
                        print("chat id2:", chatID)
                    }
                   
            }
            .toolbar {
                // MARK: Leading (left) button
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        chatListViewModel.createChat(title: "Simone secret chat")
                    }) {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Menu")
                }
            }
        }
    }
}

//#Preview {
//    ContentView(chatListViewModel: ChatListViewModel(chatRepo: ChatRepository(guestRepo: GuestRepository(db: CustomDB()), messageRepo: MessageRepository(db: CustomDB()))))
//}

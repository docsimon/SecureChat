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
                            SCLogger.logger.info(message: "Available CHAT \(model.chatID)", category: .Database)
                        }
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: UUID.self) { chatID in
                ChatView(viewModel: dep.makeChatViewModel(with: chatID), dep: dep)
                    .onAppear {
                        SCLogger.logger.info(message: "Selected CHAT \(chatID)", category: .Database)
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

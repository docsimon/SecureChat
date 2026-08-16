//
//  RouterView.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import SwiftUI

struct RouterView: View {
    
    let dep: DependencyManager
    
    var body: some View {
    
        if true {
            displayChatListScreen(chatListViewModel: dep.makeChatListViewModel(), dep: dep)
            
        } else {
            displayRegistrationScreen(registerViewModel: dep.makeRegisterOwnerViewModel())
        }
    }
}

@ViewBuilder @MainActor
func displayRegistrationScreen(registerViewModel: RegisterOwnerViewModel) -> some View {
    RegistrationView { number in
        print(number)
        await registerViewModel.registerOwner(with: number)
        print("Owner registered!")
    }
}

@ViewBuilder @MainActor
func displayChatListScreen(chatListViewModel: ChatListViewModel, dep: DependencyManager) -> some View {
    
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

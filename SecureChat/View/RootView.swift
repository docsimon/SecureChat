//
//  RootView.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import SwiftUI

/// Decides the first screen from the registration state: the chat list for a
/// registered device, the registration screen for everything else.
struct RootView: View {
    
    let dep: DependencyManager
    let registrationViewModel: RegistrationViewModel
    
    var body: some View {
        Group {
            switch registrationViewModel.phase {
            case .registered:
                displayChatListScreen(chatListViewModel: dep.makeChatListViewModel(), dep: dep)
            case .loading:
                // Saved state is read in a moment; showing the registration
                // screen first would flash it at a registered user.
                ProgressView()
            case .notRegistered, .registering, .unsupported, .failed:
                RegistrationView(viewModel: registrationViewModel)
            }
        }
        .task { await registrationViewModel.load() }
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

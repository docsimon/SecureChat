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
    ChatListScreen(chatListViewModel: chatListViewModel, dep: dep)
}

struct ChatListScreen: View {

    let chatListViewModel: ChatListViewModel
    let dep: DependencyManager
    /// Non-nil while the "Add contact" screen is up; one view model per visit.
    @State private var pairingViewModel: PairingViewModel?

    var body: some View {
    NavigationStack {
        List {
            Section("Chats") {
                ForEach(chatListViewModel.chatList) { model in
                    NavigationLink(value: model.chatID) {
                        ChatListRow(chatListModel: model)
                            .onAppear {
                                SCLogger.logger.info(message: "Available CHAT \(model.chatID)", category: .Database)
                            }
                    }
                }
            }
            // Paired contacts are not linked to chats yet: that comes with
            // sessions. Listed here so a pairing has a visible result.
            Section("Contacts") {
                if dep.contactRepo.contacts.isEmpty {
                    Text("No contacts yet. Tap the person icon to pair with someone next to you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(dep.contactRepo.contacts) { contact in
                    VStack(alignment: .leading) {
                        Text(contact.displayName)
                        Text("Paired \(contact.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
        .sheet(item: $pairingViewModel) { viewModel in
            PairingView(viewModel: viewModel)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    pairingViewModel = dep.makePairingViewModel()
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add contact")
            }
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

extension PairingViewModel: Identifiable {}

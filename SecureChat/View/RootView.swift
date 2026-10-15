//
//  RootView.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import SwiftUI
import PairingKit

/// Decides the first screen from the registration state: the chat list for a
/// registered device, the registration screen for everything else.
struct RootView: View {

    let dep: DependencyManager
    let registrationViewModel: RegistrationViewModel

    var body: some View {
        Group {
            switch registrationViewModel.phase {
            case .registered:
                ChatListScreen(dep: dep)
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

/// One chat per paired contact. Only shown to a registered device, so it is
/// also what holds the relay connection open in the foreground.
struct ChatListScreen: View {

    let dep: DependencyManager
    /// Non-nil while the "Add contact" screen is up; one view model per visit.
    @State private var pairingViewModel: PairingViewModel?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if dep.contactRepo.contacts.isEmpty {
                    Text("No contacts yet. Tap the person icon to pair with someone next to you.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(dep.contactRepo.contacts) { contact in
                    NavigationLink(value: contact.accountUUID) {
                        ChatRow(contact: contact, last: dep.messageStore.messages(with: contact.accountUUID).last,
                                presence: dep.relayConnection.peerStatus[contact.accountUUID]?.presence)
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: UUID.self) { account in
                if let contact = dep.contactRepo.contacts.first(where: { $0.accountUUID == account }) {
                    ConversationView(viewModel: dep.makeConversationViewModel(with: contact))
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
            }
        }
        // Inactive (Control Centre, an incoming call) keeps the connection;
        // only the background closes it.
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: dep.relayConnection.setActive(true)
            case .background: dep.relayConnection.setActive(false)
            default: break
            }
        }
    }
}

private struct ChatRow: View {
    let contact: PairedContact
    let last: StoredMessage?
    let presence: Presence?

    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 6) {
                Text(contact.displayName)
                PresenceDot(presence: presence)
            }
            Group {
                if let last {
                    Text(last.text).lineLimit(1)
                } else {
                    Text("Paired \(contact.pairedAt.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

extension PairingViewModel: Identifiable {}

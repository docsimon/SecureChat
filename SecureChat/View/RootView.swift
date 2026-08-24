//
//  RootView.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import SwiftUI

struct RootView: View {
    
    let dep: DependencyManager
    let rootViewModel: RootViewModel
    
    var body: some View {

        switch rootViewModel.state {
        case .registered:
            displayChatListScreen(chatListViewModel: dep.makeChatListViewModel(), dep: dep)
        case .notStarted:
            displayPhoneNumberScreen(
                phoneNumberViewModel: dep.makePhoneNumberViewModel(),
                ownerID: dep.ownerID,
                token: "12345")
        case .awaitingOTP:
            displayOTPScreen(registrationManager: dep.registrationManager, otpViewModel: dep.makeOTPViewModel(ownerID: dep.ownerID), ownerID: dep.ownerID, token: "12345")
        case .awaitingConfirmation:
            Text("Waiting for server confirmation of your number")
        }

    }
}

@ViewBuilder @MainActor
func displayPhoneNumberScreen(
    phoneNumberViewModel: PhoneNumberViewModel,
    ownerID: UUID,
    token: String) -> some View {
    PhoneNumberView(phoneNumberViewModel: phoneNumberViewModel, ownerID: ownerID, token: token)
}

func displayOTPScreen(
    registrationManager: RegistrationManager,
    otpViewModel: OTPViewModel,
    ownerID: UUID,
    token: String) -> some View {
        OTPVerificationView(viewModel: otpViewModel,
                            onChangePhoneNumber: {
            // reset the state to notStarted
            try registrationManager.resetPhoneNumber()
        },
                            onContinue: {  date in
            try registrationManager.updateRegistrationTable(otpDate: date)
        }
    )
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

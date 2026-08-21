//
//  RouterView.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import SwiftUI

struct RouterView: View {
    
    let dep: DependencyManager
    let registrationRouterViewModel: RegistrationRouterViewModel
    
    var body: some View {

        switch registrationRouterViewModel.state {
        case .registered:
            displayChatListScreen(chatListViewModel: dep.makeChatListViewModel(), dep: dep)
        case .notStarted:
            displayPhoneNumberScreen(
                registrationRouterViewModel: registrationRouterViewModel,
                phoneNumberViewModel: dep.makePhoneNumberViewModel(),
                ownerID: registrationRouterViewModel.ownerID,
                token: "12345")
        case .awaitingOTP:
            displayOTPScreen(registrationRouterViewModel: registrationRouterViewModel, otpViewModel: dep.makeOTPViewModel(ownerID: registrationRouterViewModel.ownerID), ownerID: registrationRouterViewModel.ownerID, token: "12345")
        case .awaitingConfirmation:
            Text("Waiting for server confirmation of your number")
        }

    }
}

@ViewBuilder @MainActor
func displayPhoneNumberScreen(
    registrationRouterViewModel: RegistrationRouterViewModel,
    phoneNumberViewModel: PhoneNumberViewModel,
    ownerID: UUID,
    token: String) -> some View {
    PhoneNumberView(
        onContinue: { date in
            try registrationRouterViewModel.updateRegistrationTable(phoneNumberDate: date)
        },
        phoneNumberViewModel: phoneNumberViewModel,
        ownerID: ownerID,
        token: token,
        
    )
}

func displayOTPScreen(
    registrationRouterViewModel: RegistrationRouterViewModel,
    otpViewModel: OTPViewModel,
    ownerID: UUID,
    token: String) -> some View {
        OTPVerificationView(viewModel: otpViewModel, onChangePhoneNumber: {}, onContinue: {  date in
            try await registrationRouterViewModel.updateRegistrationTable(otpDate: date)
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

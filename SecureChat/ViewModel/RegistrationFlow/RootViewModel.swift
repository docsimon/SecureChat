//
//  RootViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 16/08/2026.
//

/*
 Decides which view to show as main screen based on the registration staet of the owner.
 This viewmodle maintains the reguistration state
 */

import SwiftUI

enum RegistrationState {
    case notStarted // routes to the phone number screen
    case awaitingOTP // routes to the otp screen
    case awaitingConfirmation // routes to a waiting screen (with possible link to ask for a new otp)
    case registered // routes to the chat list
}

@MainActor @Observable
final class RootViewModel {
    
    let registrationManager: RegistrationManager
    
    init(registrationManager: RegistrationManager) {
        self.registrationManager = registrationManager
    }
    
    //MARK: Private methods
    
    var state: RegistrationState {
        let registrationPhase = registrationManager.registrationPhase
        if registrationPhase.registrationDate != nil { return .registered }
        if registrationPhase.otpCodeSentDate != nil { return .awaitingConfirmation }
        if registrationPhase.phoneNumberSentDate != nil { return .awaitingOTP }
        return .notStarted
    }
}

//
//  RouterViewModel.swift
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


@Observable @MainActor
final class RouterViewModel {
    
    let guestRepo: GuestRepository
    
    init(guestRepo: GuestRepository) {
        self.guestRepo = guestRepo
    }
    
//    
//    var state: RegistrationState {
//        if registrationDate != nil { return .registered }
//        if otpSentDate != nil { return .awaitingConfirmation }
//        if phoneNumberSentDate != nil { return .awaitingOTP }
//        return .notStarted
//    }
//    
}

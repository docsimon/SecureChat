//
//  RegistrationViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 16/08/2026.
//

/*
 Decides which view to show as main screen based on the registration staet of the owner.
 This viewmodle maintains the reguistration state
 */

import SwiftUI

@MainActor @Observable
final class RegistrationViewModel {
    
    let registrationManager: RegistrationManager
    
    init(registrationManager: RegistrationManager) {
        self.registrationManager = registrationManager
    }
}

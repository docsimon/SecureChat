//
//  PhoneNumberViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//
import SwiftUI

@MainActor @Observable
class PhoneNumberViewModel {
    
    let authService: AuthService
    let registrationManager: RegistrationManager
   
    init(authService: AuthService, registrationManager: RegistrationManager) {
        self.authService = authService
        self.registrationManager = registrationManager
    }
   
    func send(phoneNumber: String, ownerID: UUID, token: String, userName: String) async throws {
       
        do {
            
            let phoneRegistrationDate = try await authService.registerWithPhone(phone: phoneNumber, displayName: userName, userID: ownerID, pushToken: token)
            try registrationManager.updateRegistrationTable(phoneNumberDate: phoneRegistrationDate)
            
        } 
        
        
        catch {
            SCLogger.logger.error(message: "Phone number registration failed!", error: error, category: .Registration)
            fatalError()
        }
       
    }
}

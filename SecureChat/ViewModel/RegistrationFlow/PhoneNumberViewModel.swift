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
   
    init(authService: AuthService) {
        self.authService = authService
    }
   
    func send(phoneNumber: String, ownerID: UUID, token: String) async throws -> Date {
       
        do {
            let dataDTO = RegistrationDTO(userID: ownerID, phone: phoneNumber, otp: nil, token: token)
            try await authService.register(data: dataDTO, method: .post)
            return Date()
            
        } catch {
            SCLogger.logger.error(message: "Phone number registration failed!", error: error, category: .Registration)
            fatalError()
        }
       
    }
}

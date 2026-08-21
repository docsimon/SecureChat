//
//  OTPViewModel.swift
//  SecureChat
//
//  Created by doc on 19/08/2026.
//

import SwiftUI

@MainActor @Observable
final class OTPViewModel: OTPVerificationViewModel {
    
    let authService: AuthService
    let ownerID: UUID
   
    init(authService: AuthService, ownerID: UUID) {
        self.authService = authService
        self.ownerID = ownerID
    }
   
    //MARK: OTPVerificationViewModel
    
    var code: String = ""
    
    var phoneNumber: String = ""
    
    var isVerifying: Bool = false
    
    var isResending: Bool = false
    
    var resendCooldown: Int = 12
    
    var errorMessage: String?
    
    func verify() async throws -> Date {
        do {
            try await authService.verify(userID: ownerID, code: code)
            return Date()
            
        } catch {
            SCLogger.logger.error(message: "Invalid OTP code!", error: error, category: .Registration)
            throw RegistrationError.invalidOTPCode
        }
    }
    
    func resend() async {
        
    }
    
    
}

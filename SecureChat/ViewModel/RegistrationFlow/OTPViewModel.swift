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
    let registrationManager: RegistrationManager
    let ownerID: UUID
   
    init(authService: AuthService, registrationManager: RegistrationManager, ownerID: UUID) {
        self.authService = authService
        self.registrationManager = registrationManager
        self.ownerID = ownerID
    }
   
    //MARK: OTPVerificationViewModel
    
    var code: String = ""
    
    var phoneNumber: String = ""
    
    var isVerifying: Bool = false
    
    var isResending: Bool = false
    
    var resendCooldown: Int = 12
    
    var errorMessage: String?
    
    func verify() async {
        do {
            let otpCodeSentDate = try await authService.verify(userID: ownerID, code: code)
            try registrationManager.updateRegistrationTable(otpDate: otpCodeSentDate)
            
        } catch RegistrationError.invalidOTPCode(let attempts) {
            
            
            //SCLogger.logger.error(message: "Invalid OTP code!", error: , category: .Registration)
            
        } catch {
            SCLogger.logger.error(message: "Transport error", error: error, category: .Registration)
        }
           
        
    }
    
    func resend() async {
        
    }
    
    
}

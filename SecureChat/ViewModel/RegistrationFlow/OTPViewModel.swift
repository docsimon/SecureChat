//
//  OTPViewModel.swift
//  SecureChat
//
//  Created by doc on 19/08/2026.
//

import SwiftUI

@MainActor @Observable
final class OTPViewModel {
    let authService: AuthService
   
    init(authService: AuthService) {
        self.authService = authService
    }
   
    func send(otpCode: String, ownerID: UUID) async throws -> Date {
       
        do {
            try await authService.verify(userID: ownerID, code: otpCode)
            return Date()
            
        } catch {
            SCLogger.logger.error(message: "Phone number registration failed!", error: error, category: .Registration)
            fatalError()
        }
       
    }
}

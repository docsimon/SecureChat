//
//  PhoneNumberViewModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//
import SwiftUI

enum RegistrationError: Error {
    case ownerAlreadyRegistered
    case ownerDoesNOTExist
}

@MainActor @Observable
class PhoneNumberViewModel {
    
    let guestRepo: GuestRepository
    let authService: AuthService
    
    init(guestRepo: GuestRepository, authService: AuthService) {
        self.guestRepo = guestRepo
        self.authService = authService
    }
    
    func registerOwner(with phone: String) async {
       
        do {
            let owner = try fetchOwner()
            
            
            let dataDTO = RegistrationDTO(userID: owner.id, phone: phone, username: owner.username, token: getAPNsToken())
            
            try await authService.register(data: dataDTO)
            
            // update the owner registered flag
            let registeredOwner = Guest(id: owner.id, username: owner.username, isOwner: owner.isOwner, date: Date())
            try guestRepo.update(guest: registeredOwner)
            
            
        } catch {
            SCLogger.logger.error(message: "Owner doesn't exist", error: error, category: .Database)
            fatalError()
        }
       
    }
    
    
    //MARK: private functions
    
    private func fetchOwner() throws -> Guest {
        return try guestRepo.getOwner()
    }
    
    //TODO: implement the logic to get the PN token
    private func getAPNsToken() -> String {
        return "12345"
    }
    
    private func updateOwner() throws {
        
    }

}

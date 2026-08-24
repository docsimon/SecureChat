//
//  RegistrationManager.swift
//  SecureChat
//
//  Created by Simone Barbara on 23/08/2026.
//


// This type is responsible for updating and reding the registration local DB.

import Foundation
import Combine

protocol RegistrationManager {
    func updateRegistrationTable(phoneNumberDate: Date?) throws
    func updateRegistrationTable(otpDate: Date?) throws
    func updateRegistrationTable(registrationDate: Date) throws
    func resetPhoneNumber() throws
    var registrationPhase: RegistrationPhase { get }
}

@Observable @MainActor
final class RegistrationManagerImpl: @MainActor RegistrationManager {
    let registrationRepo: RegistrationRepository
    
    private(set) var registrationPhase: RegistrationPhase
    
    init(registrationRepo: RegistrationRepository, registrationPhase: RegistrationPhase = RegistrationPhase()) {
        self.registrationRepo = registrationRepo
        self.registrationPhase = registrationPhase
    }

    //MARK: Protocol RegistrationManager
        
    var phoneNumberDate: Date? {
        registrationRepo.phoneNumberSentDate
    }
    var otpDate: Date? {
        registrationRepo.otpSentDate
    }
    var registrationDate: Date? {
        registrationRepo.registrationDate
    }
    
    func updateRegistrationTable(phoneNumberDate: Date?) throws {
        registrationRepo.update(phoneSentDate: phoneNumberDate)
        registrationPhase.phoneNumberSentDate = phoneNumberDate
    }
    
    func updateRegistrationTable(otpDate: Date?) throws {
        registrationRepo.update(otpSentDate: otpDate)
        registrationPhase.otpCodeSentDate = otpDate
    }
    
    func updateRegistrationTable(registrationDate: Date) throws {
        registrationRepo.update(registrationDate: registrationDate)
        registrationPhase.registrationDate = registrationDate
    }
    
    func resetPhoneNumber() throws {
        registrationRepo.update(phoneSentDate: nil)
        registrationPhase.phoneNumberSentDate = nil
    }
}

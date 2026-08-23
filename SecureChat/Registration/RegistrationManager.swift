//
//  RegistrationManager.swift
//  SecureChat
//
//  Created by Simone Barbara on 23/08/2026.
//


// This type is responsible for updating and reding the registration local DB.

import Foundation
import Combine

enum RegistrationState {
    case notStarted // routes to the phone number screen
    case awaitingOTP // routes to the otp screen
    case awaitingConfirmation // routes to a waiting screen (with possible link to ask for a new otp)
    case registered // routes to the chat list
}

protocol RegistrationManager {
    func updateRegistrationTable(phoneNumberDate: Date?) throws
    func updateRegistrationTable(otpDate: Date?) throws
    func updateRegistrationTable(registrationDate: Date) throws
    func resetPhoneNumber() throws
    var phoneNumberDate: Date? { get }
    var otpDate: Date? { get }
    var registrationDate: Date? { get }
    var state: RegistrationState { get set }
    
}

@Observable @MainActor
final class RegistrationManagerImpl: @MainActor RegistrationManager {
    let registrationRepo: RegistrationRepository
    
    init(registrationRepo: RegistrationRepository) {
        self.registrationRepo = registrationRepo
        state = getState
    }

    //MARK: Protocol RegistrationManager
    
    var state: RegistrationState = .notStarted
    
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
    }
    
    func updateRegistrationTable(otpDate: Date?) throws {
        registrationRepo.update(otpSentDate: otpDate)
    }
    
    func updateRegistrationTable(registrationDate: Date) throws {
        registrationRepo.update(registrationDate: registrationDate)
    }
    
    func resetPhoneNumber() throws {
        registrationRepo.update(phoneSentDate: nil)
    }
    
    //MARK: Private methods
    
    var getState: RegistrationState {
        if registrationDate != nil { return .registered }
        if otpDate != nil { return .awaitingConfirmation }
        if phoneNumberDate != nil { return .awaitingOTP }
        return .notStarted
    }
    
}

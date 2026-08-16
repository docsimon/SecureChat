//
//  RegistrationRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 16/08/2026.
//

import Foundation

protocol RegistrationRepository {
    func update(phoneSentDate: Date)
    func update(otpSentDate: Date)
    func update(registrationDate: Date)
    var phoneNumberSentDate: Date? { get }
    var otpSentDate: Date? { get }
    var registrationDate: Date? { get }
}

final class RegistrationRepositoryImpl: RegistrationRepository {
    
    let db: DatabaseStrategy
    
    init(db: DatabaseStrategy) {
        self.db = db
    }
    
    //MARK: RegistrationRepository Protocol
    
    func update(phoneSentDate: Date) {
        let currentRegistrationData = getCurrentRegistrationData()
        let newRegistrationData = RegistrationData(
            ownerID: currentRegistrationData.ownerID,
            phoneNumberSentDate: phoneSentDate,
            otpSentDate: nil, // must be nil because of the registration flow
            registrationDate: nil) // same as above
        db.update(registration: newRegistrationData)
    }
    
    func update(otpSentDate: Date) {
        let currentRegistrationData = getCurrentRegistrationData()
        let newRegistrationData = RegistrationData(
            ownerID: currentRegistrationData.ownerID,
            phoneNumberSentDate: currentRegistrationData.phoneNumberSentDate,
            otpSentDate: otpSentDate,
            registrationDate: nil) // must be nil because of the registration flow
        db.update(registration: newRegistrationData)
        
    }
    
    func update(registrationDate: Date) {
        let currentRegistrationData = getCurrentRegistrationData()
        let newRegistrationData = RegistrationData(
            ownerID: currentRegistrationData.ownerID,
            phoneNumberSentDate: currentRegistrationData.phoneNumberSentDate,
            otpSentDate: otpSentDate,
            registrationDate: nil) // must be nil because of the registration flow
        db.update(registration: newRegistrationData)
    }
    
    var phoneNumberSentDate: Date? {
        return getCurrentRegistrationData().phoneNumberSentDate
    }
    
    var otpSentDate: Date? {
        return getCurrentRegistrationData().otpSentDate
    }
    
    var registrationDate: Date? {
        return getCurrentRegistrationData().registrationDate
    }
    
    
    private func getCurrentRegistrationData() -> RegistrationData {
        do {
            return try db.getRegistrationData()
        } catch {
            SCLogger.logger.error(message: "Error fetching registration data. This is a blocking issue", error: error, category: .Database)
            fatalError()
        }
    }

}


//
//  RegistrationModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import Foundation

// data sent to the auth server through the auth service to manage the registration flow
struct RegistrationDTO: Codable {
    let userID: UUID
    let phone: String
    let otp: String?
    let token: String //push notification token
}

// used by db through RegistrationRepository
struct RegistrationData {
    let ownerID: UUID
    let phoneNumberSentDate: Date?
    let otpSentDate: Date?
    let registrationDate: Date?
}

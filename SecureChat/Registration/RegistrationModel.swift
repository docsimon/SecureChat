//
//  RegistrationModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import Foundation

// data sent to the auth server through the auth service to manage the registration flow
struct RegistrationWithPhoneDTO: Codable {
    let userID: UUID
    let phone: String
    let pushToken: String //push notification token
    let displayName: String
}

struct RegistrationResponseDTO: Decodable {
    let userID: UUID
    let phone: String
    let displayName: String
    let status: RegistrationStatus     // enum with .unknown fallback
    let otpExpiresAt: Date?
    let attemptsRemaining: Int?
    let phoneSentDate: Date?
    let otpCodeSentDate: Date?
    let registeredAt: Date?
}

enum RegistrationStatus: Decodable {
    case pendingVerification
    case verified
    case unknown(String)

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "pending_verification": self = .pendingVerification
        case "verified":             self = .verified
        default:                     self = .unknown(raw)
        }
    }
}

struct RegistrationWithEmailDTO: Codable {
    let userID: UUID
    let email: String
    let pushToken: String //push notification token
    let displayName: String
}

struct RegistrationOTPVerificationDTO: Codable {
    let userID: UUID
    let code: String
}

struct RegistrationUpdatePhone: Codable {
    let phone: String
}



// used by db through RegistrationRepository
struct RegistrationData {
    let ownerID: UUID
    let phoneNumberSentDate: Date?
    let otpSentDate: Date?
    let registrationDate: Date?
}

// used for the payload sent by the auth server in case of error

struct PayloadErrorResponse: Decodable {
    let error: APIError
    let attemptsRemaining: Int?
    let retryAfterMs: Int?
}

// Registration dates used by the RegistrationManager to update the reigstration state in the rootViewModel

struct RegistrationPhase {
    var phoneNumberSentDate: Date?
    var otpCodeSentDate: Date?
    var registrationDate: Date? // this is recorded after the otp code has been verified
}

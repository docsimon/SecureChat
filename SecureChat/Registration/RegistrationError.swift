//
//  RegistrationError.swift
//  SecureChat
//
//  Created by Simone Barbara on 21/08/2026.
//

enum RegistrationError: Error {
    case ownerAlreadyRegistered
    case ownerDoesNotExist
    case invalidPhoneNumber
    case invalidOTPCode(attemptsRemaining: Int)
    case invalidState(RegistrationState)
    case resendTooSoon(retryAfterMs: Int)
    case codeExpired
    case tooManyAttempts
    case unknownUser
    case phoneTaken
    case phoneRequired
    case unexpected(status: Int, code: String)
    case unknown(String)
}

enum APIError: Decodable {
    case invalidCode, codeExpired, tooManyAttempts, resendTooSoon
    case unknownUser, phoneTaken, phoneRequired
    case unknown(String)          // ← forward compatibility

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "invalid_code":      self = .invalidCode
        case "code_expired":      self = .codeExpired
        case "too_many_attempts": self = .tooManyAttempts
        case "resend_too_soon":   self = .resendTooSoon
        case "unknown_user":      self = .unknownUser
        case "phone_taken":       self = .phoneTaken
        case "phone_required":    self = .phoneRequired
        default:                  self = .unknown(raw)   // never throws
        }
    }
}



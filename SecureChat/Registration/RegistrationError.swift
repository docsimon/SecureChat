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
    case invalidOTPCode
}


//
//  NetworkDTOModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

import Foundation

struct RegistrationDTO: Codable {
    let phoneNumber: String
    let username: String
    let token: String //push notification token
}

//
//  GuestModel.swift
//  SecureChat
//
//  Created by Simone Barbara on 01/10/2025.
//

import Foundation

struct Guest: Equatable {
    let id: UUID
    let username: String
    let isOwner: Bool
    let date: Date
    let isRegistered: Bool
}

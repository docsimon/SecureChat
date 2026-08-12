//
//  GuestRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol GuestRepositoryProtocol {
    func getGuest(id: UUID) throws -> Guest
    func addGuest(username: String, id: UUID?)
}

final class GuestRepository: GuestRepositoryProtocol {
    
    let db: DatabaseStrategy

    func getGuest(id: UUID) throws -> Guest {
        return try db.getGuest(id: id)
    }
    
    func addGuest(username: String, id: UUID?) {
        
        let guestID: UUID = {
            guard let id = id else {
                return UUID()
            }
            return id
        }()

        let newGuest = Guest(id: guestID, username: username, isOwner: false)
        db.addGuest(guest: newGuest)
    }
    
    init(db: DatabaseStrategy = CustomDB.shared) {
        self.db = db
    }

    
}

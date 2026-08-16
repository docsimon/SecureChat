//
//  GuestRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol GuestRepository {
    func getGuest(id: UUID) throws -> Guest
    func addGuest(username: String, id: UUID?)
    func getOwner() throws -> Guest
    func update(guest: Guest) throws
}

final class GuestRepositoryImpl: GuestRepository {
    
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

        let newGuest = Guest(id: guestID, username: username, isOwner: false, date: Date())
        db.addGuest(guest: newGuest)
    }
    
    func getOwner() throws -> Guest {
        return try db.getOwner()
    }
    
    func update(guest: Guest) throws {
        return db.update(guest: guest)
    }
    
    init(db: DatabaseStrategy = CustomDB.shared) {
        self.db = db
    }

}

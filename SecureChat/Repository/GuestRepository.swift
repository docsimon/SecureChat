//
//  GuestRepository.swift
//  SecureChat
//
//  Created by Simone Barbara on 02/10/2025.
//

import Foundation

protocol GuestRepositoryProtocol {
    func getGuest(id: UUID) -> Guest?
    func addGuest(username: String, id: UUID)
}

final class GuestRepository: GuestRepositoryProtocol {
    
    static let shared = GuestRepository()
    let db: DatabaseStrategy

    func getGuest(id: UUID) -> Guest? {
        return db.getGuest(id: id)
    }
    
    func addGuest(username: String, id: UUID) {
        let newGUest = Guest(id: id, username: username)
        db.addGuest(guest: newGUest)
    }
    
    init(db: DatabaseStrategy = CustomDB.shared) {
        self.db = db
    }

    
}

//
//  GuestRepository.swift
//  SecureChat
//
//  Created by doc on 02/10/2025.
//

import Foundation

protocol GuestRepositoryProtocol {
    func getGuest(id: UUID) -> Guest?
    var guest: [Guest] { get }
}

final class GuestRepository: GuestRepositoryProtocol {
    
    func getGuest(id: UUID) -> Guest? {
        return guest.filter { $0.id == id }.first
    }
    
    var guest: [Guest] {
        return [
            GuestFactory.shared.make(id: UUID(uuidString: "123e4567-e89b-12d3-a456-426614174000")!, username: "Simone"),
            GuestFactory.shared.make(id: UUID(uuidString: "987fcdeb-1234-5678-9012-34567890abcd")!, username: "Ciccio"),
            GuestFactory.shared.make(id: UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!, username: "Formaggio"),
            GuestFactory.shared.make(id: UUID(uuidString: "6ba7b810-9dad-11d1-80b4-00c04fd430c8")!, username: "Cippalippa"),
            GuestFactory.shared.make(id: UUID(uuidString: "f47ac10b-58cc-4372-a567-0e02b2c3d479")!, username: "Charlie"),
            GuestFactory.shared.make(id: UUID(uuidString: "1b671a64-40d5-491e-99b0-da01ff1f3341")!, username: "Topasky")
        ]
    }
    
}

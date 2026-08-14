//
//  Router.swift
//  SecureChat
//
//  Created by Simone Barbara on 14/08/2026.
//

/*
 Decides which view to show as main screen based on the registration of the owner.
 If the owner is not registered on the auth server yet, the registration flow will be show.
 Otherwise, if already reigstered, the chat list screen will be displayed.
 */

struct Router {
    let guestRepo: GuestRepository
    
    init(guestRepo: GuestRepository) {
        self.guestRepo = guestRepo
    }
    
    var isRegistered: Bool {
        get throws {
            let owner = try guestRepo.getOwner()
            return owner.isRegistered
        }
    }
}



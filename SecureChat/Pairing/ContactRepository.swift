//
//  ContactRepository.swift
//  SecureChat
//
//  The people this device has paired with.
//

import Foundation
import PairingKit

@MainActor @Observable
final class ContactRepository {

    private(set) var contacts: [PairedContact] = []

    @ObservationIgnored private let db: DatabaseStrategy

    init(db: DatabaseStrategy) {
        self.db = db
        do {
            contacts = try db.fetchContacts()
        } catch {
            SCLogger.logger.error(message: "Could not read contacts", error: error, category: .Database)
        }
    }

    func add(_ contact: PairedContact) throws {
        try db.addContact(contact)
        contacts.append(contact)
    }
}

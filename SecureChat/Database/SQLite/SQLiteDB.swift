//
// SQLiteDB.swift
// SecureChat
//
// Created by Simone Barbara on 18/10/2025.
// All Rights Reserved.

import SQLite
import Foundation
import PairingKit

final class SQLiteDB: DatabaseStrategy {

    private let db: Connection
    private let schema: SQLiteSchemaProtocol

    /// The app passes `DatabaseLocation.prepare()`; tests pass ":memory:".
    init(path: String, schema: SQLiteSchemaProtocol = SQLiteSchema()) throws {
        self.db = try Connection(path)
        self.schema = schema
        // Deleted rows are overwritten, not left in free pages.
        try db.run("PRAGMA secure_delete = ON")
        try schema.dropPlaceholderTables(db: db)
        try schema.setAsidePlaintextMessages(db: db)
        try schema.createContactsTable(db: db)
        try schema.createMessagesTable(db: db)
    }

    //MARK: DatabaseStrategy

    func fetchContacts() throws -> [PairedContact] {
        try db.prepare(ContactsTable.contacts.order(ContactsTable.pairedAt)).map { row in
            PairedContact(identityPublicKey: row[ContactsTable.identityPublicKey],
                          accountUUID: row[ContactsTable.accountUUID],
                          displayName: row[ContactsTable.displayName],
                          pairedAt: row[ContactsTable.pairedAt])
        }
    }

    func addContact(_ contact: PairedContact) throws {
        try db.run(ContactsTable.contacts.insert(
            ContactsTable.identityPublicKey <- contact.identityPublicKey,
            ContactsTable.accountUUID <- contact.accountUUID,
            ContactsTable.displayName <- contact.displayName,
            ContactsTable.pairedAt <- contact.pairedAt
        ))
        // The name is what the other side chose to call itself; not logged.
        SCLogger.logger.info(message: "Contact record created!", category: .Database)
    }

    func fetchMessages() throws -> [SealedMessage] {
        try db.prepare(MessagesTable.messages.order(MessagesTable.date)).map { row in
            SealedMessage(id: row[MessagesTable.id],
                          peer: row[MessagesTable.peer],
                          sealedText: row[MessagesTable.sealedText],
                          date: row[MessagesTable.date],
                          status: StoredMessage.Status(rawValue: row[MessagesTable.status]) ?? .notDelivered)
        }
    }

    func addMessage(_ message: SealedMessage) throws {
        try db.run(MessagesTable.messages.insert(
            MessagesTable.id <- message.id,
            MessagesTable.peer <- message.peer,
            MessagesTable.sealedText <- message.sealedText,
            MessagesTable.date <- message.date,
            MessagesTable.status <- message.status.rawValue
        ))
    }

    func updateStatus(of ids: [UUID], to status: StoredMessage.Status) throws {
        guard !ids.isEmpty else { return }
        try db.run(MessagesTable.messages.filter(ids.contains(MessagesTable.id))
            .update(MessagesTable.status <- status.rawValue))
    }

    func deleteMessages(with peer: UUID) throws {
        try db.run(MessagesTable.messages.filter(MessagesTable.peer == peer).delete())
    }

    func plaintextMessages() throws -> [StoredMessage] {
        guard try db.tableExists(PlaintextMessagesTable.name) else { return [] }
        let table = PlaintextMessagesTable.messages
        return try db.prepare(table.order(MessagesTable.date)).map { row in
            StoredMessage(id: row[MessagesTable.id],
                          peer: row[MessagesTable.peer],
                          text: row[PlaintextMessagesTable.text],
                          date: row[MessagesTable.date],
                          status: StoredMessage.Status(rawValue: row[MessagesTable.status]) ?? .notDelivered)
        }
    }

    func dropPlaintextMessages() throws {
        guard try db.tableExists(PlaintextMessagesTable.name) else { return }
        try db.run(PlaintextMessagesTable.messages.drop())
        // Rewrites the file: nothing of the old pages survives in it.
        try db.vacuum()
    }
}

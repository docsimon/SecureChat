//
// SQLiteSchema.swift
// SecureChat
//
// Created by Simone Barbara on 19/10/2025.
// All Rights Reserved.


import Foundation
import SQLite

protocol SQLiteSchemaProtocol {
    func dropPlaceholderTables(db: Connection) throws
    func createContactsTable(db: Connection) throws
    func createMessagesTable(db: Connection) throws
}


// Tables Schema

/// People paired with by QR scan (Architecture/pairing-workflow.md): an
/// identity key and a routing address. A chat is a contact.
enum ContactsTable {
    static let name = "contacts"
    static let contacts = Table(name)
    static let identityPublicKey = SQLite.Expression<Data>("identityPublicKey")
    static let accountUUID = SQLite.Expression<UUID>("accountUUID")
    static let displayName = SQLite.Expression<String>("displayName")
    static let pairedAt = SQLite.Expression<Date>("pairedAt")
}

/// Messages exchanged with contacts, keyed by the contact's account id.
/// Plain text for now: encrypting it is the next storage step
/// (session-workflow.md, "Message storage").
enum MessagesTable {
    static let name = "messages"
    static let messages = Table(name)
    static let id = SQLite.Expression<UUID>("id")
    static let peer = SQLite.Expression<UUID>("peer")
    static let text = SQLite.Expression<String>("text")
    static let date = SQLite.Expression<Date>("date")
    static let status = SQLite.Expression<Int>("status")
}

struct SQLiteSchema: SQLiteSchemaProtocol {

    //MARK: Placeholder tables

    func dropPlaceholderTables(db: Connection) throws {
        guard try db.tableExists(SQLiteConstants.placeholderMarkerTable) else { return }
        for table in SQLiteConstants.placeholderTables {
            try db.run(Table(table).drop(ifExists: true))
        }
        SCLogger.logger.info(message: "Placeholder chat tables dropped", category: .Database)
    }

    //MARK: Contacts Table

    func createContactsTable(db: Connection) throws {

        guard !(try db.tableExists(ContactsTable.name)) else {
            SCLogger.logger.info(message: "Contacts table already exists!", category: .Database)
            return
        }

        try db.run(ContactsTable.contacts.create { t in
            t.column(ContactsTable.identityPublicKey, primaryKey: true)
            // One contact per routing address as well as per key.
            t.column(ContactsTable.accountUUID, unique: true)
            t.column(ContactsTable.displayName)
            t.column(ContactsTable.pairedAt)
        })

        SCLogger.logger.info(message: "Contacts table created!", category: .Database)
    }

    //MARK: Messages Table

    func createMessagesTable(db: Connection) throws {

        guard !(try db.tableExists(MessagesTable.name)) else {
            SCLogger.logger.info(message: "Messages table already exists!", category: .Database)
            return
        }

        try db.run(MessagesTable.messages.create { t in
            t.column(MessagesTable.id, primaryKey: true)
            t.column(MessagesTable.peer)
            t.column(MessagesTable.text)
            t.column(MessagesTable.date)
            t.column(MessagesTable.status)
        })
        try db.run(MessagesTable.messages.createIndex(MessagesTable.peer, MessagesTable.date))

        SCLogger.logger.info(message: "Messages table created!", category: .Database)
    }
}

extension Connection {
    func tableExists(_ name: String) throws -> Bool {
        let count = try scalar(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name = ?",
            name
        ) as? Int64 ?? 0
        return count > 0
    }
}

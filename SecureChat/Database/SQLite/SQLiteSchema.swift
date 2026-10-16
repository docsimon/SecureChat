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
    func setAsidePlaintextMessages(db: Connection) throws
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

/// Messages exchanged with contacts, keyed by the contact's account id. The
/// text is sealed with the contact's key (storage option B,
/// session-workflow.md, "Message storage"); who, when and the status are not.
enum MessagesTable {
    static let name = "messages"
    static let messages = Table(name)
    static let id = SQLite.Expression<UUID>("id")
    static let peer = SQLite.Expression<UUID>("peer")
    static let sealedText = SQLite.Expression<Data>("sealedText")
    static let date = SQLite.Expression<Date>("date")
    static let status = SQLite.Expression<Int>("status")
}

/// The plain-text messages table of builds before storage option B, renamed
/// out of the way until its rows are sealed into `messages`.
enum PlaintextMessagesTable {
    static let name = "messages_plaintext"
    static let messages = Table(name)
    static let text = SQLite.Expression<String>("text")
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

    //MARK: Plaintext messages

    /// A `messages` table with a `text` column is from before storage option
    /// B: renamed, for `MessageStore` to seal and then drop.
    func setAsidePlaintextMessages(db: Connection) throws {
        guard try db.tableExists(MessagesTable.name),
              try db.columnExists("text", in: MessagesTable.name),
              !(try db.tableExists(PlaintextMessagesTable.name)) else { return }
        try db.run("ALTER TABLE \(MessagesTable.name) RENAME TO \(PlaintextMessagesTable.name)")
        // Its indexes kept their names, which the new table's would reuse.
        let indexes = try db.prepare("""
            SELECT name FROM sqlite_master
            WHERE type = 'index' AND tbl_name = ? AND name NOT LIKE 'sqlite_autoindex%'
            """, PlaintextMessagesTable.name).compactMap { $0[0] as? String }
        for index in indexes { try db.run("DROP INDEX \"\(index)\"") }
        SCLogger.logger.info(message: "Plain-text messages set aside for sealing", category: .Database)
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
            t.column(MessagesTable.sealedText)
            t.column(MessagesTable.date)
            t.column(MessagesTable.status)
        })
        try db.run(MessagesTable.messages.createIndex(MessagesTable.peer, MessagesTable.date))

        SCLogger.logger.info(message: "Messages table created!", category: .Database)
    }
}

extension Connection {
    func columnExists(_ column: String, in table: String) throws -> Bool {
        try prepare("PRAGMA table_info(\(table))").contains { row in (row[1] as? String) == column }
    }

    func tableExists(_ name: String) throws -> Bool {
        let count = try scalar(
            "SELECT count(*) FROM sqlite_master WHERE type='table' AND name = ?",
            name
        ) as? Int64 ?? 0
        return count > 0
    }
}

//
// SQLiteSchema.swift
// SecureChat
//
// Created by Simone Barbara on 19/10/2025.
// All Rights Reserved.


import Foundation
import SQLite

protocol SQLiteSchemaProtocol {
    func createGuestTable(db: Connection) throws
    func createChatTable(db: Connection) throws
    func createChatGuestJointTable(db: Connection) throws
    func createMessageTable(db: Connection) throws
}


// Tables Schema


enum GuestsTable {
    
    static let name = "guests"
    static let guests = Table(name)
    static let id = SQLite.Expression<UUID>("id")
    static let date = SQLite.Expression<Date>("date")
    static let username = SQLite.Expression<String>("username")
    static let isOwner = SQLite.Expression<Bool>("isOwner")
}

struct SQLiteSchema: SQLiteSchemaProtocol {
    
    func createGuestTable(db: Connection) throws {
        
        // Check if table guests exists, otherwise return
        guard !(try db.tableExists(GuestsTable.name)) else {
            SCLogger.logger.info(message: "Guests table already exists!", category: .Database)
            return
        }
        
      
        
        
        try db.run(GuestsTable.guests.create { t in
            t.column(GuestsTable.id, primaryKey: true)
            t.column(GuestsTable.date)
            t.column(GuestsTable.username)
            t.column(GuestsTable.isOwner)
        })
        
        SCLogger.logger.info(message: "Guests table created!", category: .Database)
        
        // Add owner
        do {
            try addOwner(db: db)
        } catch {
            SCLogger.logger.error(message: "Failer to create owner", category: .Database)
        }
    }
    
    func createChatTable(db: Connection) throws {
        
        // Check if table guests exists, otherwise return
        guard !doesTableExist(db: db, table: "chats") else {
            SCLogger.logger.info(message: "Chats table already exists!", category: .Database)
            return
        }
        
        let chats = Table("chats")
        let id = SQLite.Expression<UUID>("id")
        let title = SQLite.Expression<String>("title")
        let date = SQLite.Expression<Date>("date")
        
        try db.run(chats.create { t in
            t.column(id, primaryKey: true)
            t.column(title)
            t.column(date)
        })
        
        SCLogger.logger.info(message: "Chats table created!", category: .Database)
    }
    
    func createChatGuestJointTable(db: Connection) throws {
        
        // Check if table guests exists, otherwise return
        guard !doesTableExist(db: db, table: "chat_guests") else {
            SCLogger.logger.info(message: "Chat_guests table already exists!", category: .Database)
            return
        }
        
        let chats = Table("chats")
        let guests = Table("guests")
        let chatGuests = Table("chat_guests")
        
        let chatID = Expression<ChatID>("chatID")
        let guestID = Expression<GuestID>("guestID")
        
        try db.run(chatGuests.create { t in
            t.column(chatID)
            t.column(guestID)
            t.foreignKey(chatID, references: chats, chatID)
            t.foreignKey(guestID, references: guests, guestID)
            t.primaryKey(chatID, guestID) // Composite primary key
        })
        
        SCLogger.logger.info(message: "Chat_guests table created!", category: .Database)
    }
    
    func createMessageTable(db: Connection) throws {

        // Check if table guests exists, otherwise return
        guard !doesTableExist(db: db, table: "messages") else {
            SCLogger.logger.info(message: "Messages table already exists!", category: .Database)
            return
        }
        
        let messages = Table("messages")
        let id = SQLite.Expression<MessageID>("id")
        let chatID = SQLite.Expression<ChatID>("chatID")
        let guestID = SQLite.Expression<GuestID>("guestID") // sender
        let content = SQLite.Expression<String>("content")
        let date = SQLite.Expression<Date>("date")
        let ttl = SQLite.Expression<Int>("ttl")
        let isOwner = SQLite.Expression<Bool>("isOwner")
        
        try db.run(messages.create { t in
            t.column(id, primaryKey: true)
            t.column(chatID)
            t.column(guestID)
            t.column(content)
            t.column(date)
            t.column(ttl)
            t.column(isOwner)
        })
        
        SCLogger.logger.info(message: "Messages table created!", category: .Database)
    }
    
    private func doesTableExist(db: Connection, table: String) -> Bool {
        
        do {
            let tableExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='\(table)';") as? Int64 ?? 0
            if tableExists == 0 {
                return false
            }
        } catch {
            SCLogger.logger.error(message: LogMessage.SQLiteTableError, error: error, category: .Database)
        }
        return true
    }
    
    private func addOwner(db: Connection) throws {
        
        
        
        guard try db.tableExists(GuestsTable.name) else {
            return
        }
        
        do {
           
            let guestID = UUID()
            let ownerInsert = GuestsTable.guests.insert(
                GuestsTable.id <- guestID,
                GuestsTable.date <- Date(),
                GuestsTable.username <- "Owner",
                GuestsTable.isOwner <- true
            
            )
            
            try db.run(ownerInsert)
            SCLogger.logger.info(message: "Guest Owner record created! \(guestID)", category: .Database)
            
        } catch {
            SCLogger.logger.error(message: "Error creating Guest Owner record:", error: error, category: .Database)
        }
    }
    
    private func printUsers(db: Connection, table: Table, tabName: String) {
        
        guard doesTableExist(db: db, table: tabName) else {
            SCLogger.logger.error(message: "Error fetching users from guests, table doesn't exist or is Empty ", category: .Database)
            return
        }
    
        do {
            let id = SQLite.Expression<UUID>("id")
            let username = SQLite.Expression<String>("username")
            let isOwner = SQLite.Expression<Bool>("isOwner")
            
            for row in try db.prepare(table) {
                print("id: \(row[id]), User: \(row[username]), isOwner: \(row[isOwner])")
            }
        } catch {
            SCLogger.logger.error(message: "Error fetching users from guests:", error: error, category: .Database)
        }
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

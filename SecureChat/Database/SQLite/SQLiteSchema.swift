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

enum ChatsTable {
    
    static let name = "chats"
    static let chats = Table(name)
    static let id = SQLite.Expression<UUID>("id")
    static let title = SQLite.Expression<String>("title")
    static let date = SQLite.Expression<Date>("date")
}

enum ChatsGuestsTable {
    
    static let name = "chats_guests"
    static let chatsGuests = Table(name)
    static let chats = ChatsTable.chats
    static let guests = GuestsTable.guests
    static let chatID = Expression<ChatID>("chatID")
    static let guestID = Expression<GuestID>("guestID")
}

enum MessagesTable {
    static let name = "messages"
    static let messages = Table(name)
    static let id = SQLite.Expression<MessageID>("id")
    static let chatID = SQLite.Expression<ChatID>("chatID")
    static let guestID = SQLite.Expression<GuestID>("guestID") // sender
    static let content = SQLite.Expression<String>("content")
    static let date = SQLite.Expression<Date>("date")
    static let ttl = SQLite.Expression<Int>("ttl")
    static let isOwner = SQLite.Expression<Bool>("isOwner")
}

struct SQLiteSchema: SQLiteSchemaProtocol {
    
    //MARK: Guests Table
    
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
    
    //MARK: Chats Table
    
    func createChatTable(db: Connection) throws {
        
        // Check if table guests exists, otherwise return
        guard !(try db.tableExists(ChatsTable.name)) else {
            SCLogger.logger.info(message: "Chats table already exists!", category: .Database)
            return
        }
        
       
        
        try db.run(ChatsTable.chats.create { t in
            t.column(ChatsTable.id, primaryKey: true)
            t.column(ChatsTable.title)
            t.column(ChatsTable.date)
        })
        
        SCLogger.logger.info(message: "Chats table created!", category: .Database)
    }
    
    //MARK: ChatsGuests Table
    
    func createChatGuestJointTable(db: Connection) throws {
        
        // Check if table guests exists, otherwise return
        guard !(try db.tableExists(ChatsGuestsTable.name)) else {
            SCLogger.logger.info(message: "Chat_guests table already exists!", category: .Database)
            return
        }
        
        try db.run(ChatsGuestsTable.chatsGuests.create { t in
            t.column(ChatsGuestsTable.chatID)
            t.column(ChatsGuestsTable.guestID)
            t.foreignKey(ChatsGuestsTable.chatID, references: ChatsGuestsTable.chats, ChatsGuestsTable.chatID)
            t.foreignKey(ChatsGuestsTable.guestID, references: ChatsGuestsTable.guests, ChatsGuestsTable.guestID)
            t.primaryKey(ChatsGuestsTable.chatID, ChatsGuestsTable.guestID) // Composite primary key
        })
        
        SCLogger.logger.info(message: "Chat_guests table created!", category: .Database)
    }
    
    //MARK: Messages Table
    
    func createMessageTable(db: Connection) throws {

        // Check if table guests exists, otherwise return
        guard !(try db.tableExists(MessagesTable.name)) else {
            SCLogger.logger.info(message: "Messages table already exists!", category: .Database)
            return
        }
        
        
        try db.run(MessagesTable.messages.create { t in
            t.column(MessagesTable.id, primaryKey: true)
            t.column(MessagesTable.chatID)
            t.column(MessagesTable.guestID)
            t.column(MessagesTable.content)
            t.column(MessagesTable.date)
            t.column(MessagesTable.ttl)
            t.column(MessagesTable.isOwner)
        })
        
        SCLogger.logger.info(message: "Messages table created!", category: .Database)
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

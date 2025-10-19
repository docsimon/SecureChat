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

struct SQLiteSchema: SQLiteSchemaProtocol {
    
    func createGuestTable(db: Connection) throws {
        // Check if table guests exists, otherwise return
        let tableExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='guests';") as? Int64 ?? 0
        
        guard tableExists == 0 else {
            SCLogger.logger.info(message: "Guests table already exists! ", category: .Database)
            return
        }
        
        
        let guests = Table("guests")
        let id = SQLite.Expression<UUID>("id")
        let username = SQLite.Expression<String>("name")
        
        try db.run(guests.create { t in
            t.column(id, primaryKey: true)
            t.column(username)
            
        })
    }
    
    func createChatTable(db: Connection) throws {
        // Check if table guests exists, otherwise return
        let tableExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='chats';") as? Int64 ?? 0
        
        guard tableExists == 0 else {
            SCLogger.logger.info(message: "Chats table already exists! ", category: .Database)
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
    }
    
    func createChatGuestJointTable(db: Connection) throws {
        let tableExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='chat_guests';") as? Int64 ?? 0
        
        guard tableExists == 0 else {
            SCLogger.logger.info(message: "Chat_guests table already exists! ", category: .Database)
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
    }
    
    func createMessageTable(db: Connection) throws {
        // Check if table guests exists, otherwise return
        let tableExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='messages';") as? Int64 ?? 0
        
        guard tableExists == 0 else {
            SCLogger.logger.info(message: "Messages table already exists! ", category: .Database)
            return
        }
        
        let chats = Table("messages")
        let id = SQLite.Expression<MessageID>("id")
        let chatID = SQLite.Expression<ChatID>("chatID")
        let guestID = SQLite.Expression<GuestID>("guestID")
        let content = SQLite.Expression<String>("content")
        let date = SQLite.Expression<Date>("date")
        let ttl = SQLite.Expression<Int>("ttl")
        
        try db.run(chats.create { t in
            t.column(id, primaryKey: true)
            t.column(chatID)
            t.column(guestID)
            t.column(content)
            t.column(date)
            t.column(ttl)
        })
    }
}

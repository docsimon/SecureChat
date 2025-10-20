//
// SQLiteDB.swift
// SecureChat  
//
// Created by Simone Barbara on 18/10/2025.                               
// All Rights Reserved.                                                         

import SQLite
import Foundation

final class SQLiteDB: DatabaseStrategy {
        
    private let db: Connection
    private let path: String
    private let schema: SQLiteSchemaProtocol
    
    
    init(path: String = SQLiteConstants.sqlPath, schema: SQLiteSchemaProtocol = SQLiteSchema()) throws {
        self.path = path
        self.db = try SQLiteDB.createDB(with: path)
        self.schema = schema
        createTablesIfNeeded(db: db)
        chatList = try fetchChatList()
    }
    
    //MARK: DatabaseStrategy
    
    func saveChat(chat: Chat) {
        
    }
    
    func saveGuest(guest: Guest) {
        
    }
    
    func saveMessage(message: Message) {
        
    }
    
    func getMessage(id: MessageID) -> Message? {
        return nil
    }
    
    func getGuest(id: GuestID) -> Guest? {
        return nil
    }
    
    func getChat(id: ChatID) -> Chat? {
        return nil
    }
    
    func bootstrap() throws {
        createTablesIfNeeded(db: self.db)
    }
    
    func createChat(title: String) {
        do {
            // Update chats table
            let chats = Table("chats")
            let id = SQLite.Expression<UUID>("id")
            let title = SQLite.Expression<String>("title")
            let date = SQLite.Expression<Date>("date")
            let chatIdentifier = UUID()
            
            let addChatQuery = chats.insert(
                id <- chatIdentifier,
                title <- title,
                date <- Date()
            )
            
            try db.run(addChatQuery)
            
            // update chat_guests table
            let chatGuests = Table("chat_guests")
            
            let chatID = Expression<ChatID>("chatID")
            let guestID = Expression<GuestID>("guestID")
            let guestIdentifier = try getOwner()
            
            let addChatGuestsQuery = chatGuests.insert (
                chatID <- chatIdentifier,
                guestID <- guestIdentifier
            )
            
            try db.run(addChatGuestsQuery)

            SCLogger.logger.info(message: "Chat \"\(title)\" record created!", category: .Database)
            SCLogger.logger.info(message: "ChatID: \(chatIdentifier) GuestID: \(guestIdentifier)", category: .Database)
            
            chatList = try fetchChatList()
            
        } catch {
            SCLogger.logger.error(message: "Error creating Chat \"\(title)\" record:", error: error, category: .Database)
        }
    }
    
    var chatList: [ChatListModel] = []
       

    
    //MARK: Private methods
    
    var _chatList = [ChatListModel]()
    
    private static func createDB(with path: String) throws -> Connection {
            let db = try Connection(path)
            //db?.busyTimeout = 5
            return db
    }
    
    private func createTablesIfNeeded(db: Connection) {
        do {
            try schema.createGuestTable(db: db)
            try schema.createChatTable(db: db)
            try schema.createChatGuestJointTable(db: db)
            try schema.createMessageTable(db: db)
        } catch {
            SCLogger.logger.error(message: LogMessage.SQLiteTableError, error: error, category: .Database)
        }
    }
    
    private func getOwner() throws -> UUID {
        let guests = Table("guests")
        let id = SQLite.Expression<UUID>("id")
        let isOwner = SQLite.Expression<Bool>("isOwner")
        
        if let row = try db.pluck(guests.filter(isOwner == true)) {
            return row[id]
        } else {
            throw DBError.ownerIDNotFound
        }
    }
    
//    private func fetchSingleChat() throws -> [Chat] {
//        
//        let messageTable = Table("messages")
//        let guestTable = Table("guests")
//        let guest_id = SQLite.Expression<UUID>("id")
//        let chatTable = Table("chats")
//        let id = SQLite.Expression<UUID>("id")
//        let title = SQLite.Expression<String>("title")
//        let date = SQLite.Expression<Date>("date")
//        
//        var result: [Chat] = []
//        
//        for chat in try db.prepare(chatTable) {
//            var guestsID = [GuestID]()
//            for guest in try db.prepare(guestTable) {
//                guestsID.append(guest[id])
//            }
//            
//            let newChat = Chat(id: chat[id], title: chat[title], guests: guestsID, messages: [], date: chat[date])
//            
//            result.append(newChat)
//            
//        }
//        
//        return result
//    }
    
    private func fetchChatList() throws -> [ChatListModel] {
        
        let chatTable = Table("chats")
        let id = SQLite.Expression<UUID>("id")
        let title = SQLite.Expression<String>("title")
        let date = SQLite.Expression<Date>("date")
        
        var result: [ChatListModel] = []
        
        for chat in try db.prepare(chatTable) {
           let chatList = ChatListModel(chatID: chat[id], title: chat[title], date: chat[date])
            result.append(chatList)
        }
        
        return result
    }
}

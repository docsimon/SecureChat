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
    private let notificationCenter: NotificationCenter
    
    
    init(path: String = SQLiteConstants.sqlPath, schema: SQLiteSchemaProtocol = SQLiteSchema(), notificationCenter: NotificationCenter = NotificationCenter.default) throws {
        self.path = path
        self.db = try SQLiteDB.createDB(with: path)
        self.schema = schema
        self.notificationCenter = notificationCenter
        createTablesIfNeeded(db: db)
        chatList = try fetchChatList()
    }
    
    //MARK: DatabaseStrategy
    
    func saveChat(chat: Chat) {
        
    }
    
    func saveGuest(guest: Guest) {
        
    }
    
    func saveMessage(message: Message) {
        do {
            // Update messages table
            let messagesTable = Table("messages")
            let id = SQLite.Expression<MessageID>("id")
            let chatID = SQLite.Expression<ChatID>("chatID")
            let guestID = SQLite.Expression<GuestID>("guestID") // sender
            let content = SQLite.Expression<String>("content")
            let date = SQLite.Expression<Date>("date")
            let ttl = SQLite.Expression<Int>("ttl")
            
            let addMessageQuery = messagesTable.insert(
                id <- message.id,
                chatID <- message.chatID,
                guestID <- message.guestID,
                content <- message.content,
                date <- message.date,
                ttl <- message.ttl
            )
            
            try db.run(addMessageQuery)
            SCLogger.logger.info(message: "Message record created!", category: .Database)
            notificationCenter.post(Notification(name: ChatNotification.newMessage, object: message))

        } catch {
            SCLogger.logger.error(message: "Error creating message record:", error: error, category: .Database)
        }
    }
    
    func getMessage(id: MessageID) -> Message? {
        do {
            // Update messages table
            let messagesTable = Table("messages")
            let m_id = SQLite.Expression<MessageID>("id")
            let chatID = SQLite.Expression<ChatID>("chatID")
            let guestID = SQLite.Expression<GuestID>("guestID") // sender
            let content = SQLite.Expression<String>("content")
            let date = SQLite.Expression<Date>("date")
            let ttl = SQLite.Expression<Int>("ttl")
            
            if let row = try db.pluck(messagesTable.filter(m_id == id)) {
                return Message(id: row[m_id], chatID: row[chatID], guestID: row[guestID], content: row[content], date: row[date], ttl: row[ttl])
            } else {
                SCLogger.logger.error(message: "Message not found", category: .Message)
            }
            
        } catch {
            SCLogger.logger.error(message: "Error fetching the message:", error: error, category: .Database)
        }
    
        return nil
    }
    
    func getGuest(id: GuestID) -> Guest? {
        return nil
    }
    
    func getChat(id: ChatID) -> Chat? {
        do {
            return try fetchSingleChat(chatID: id)
        } catch {
            SCLogger.logger.error(message: "Error while fetching the chat from DB", error: error, category: .Database)
        }
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
            let row_title = SQLite.Expression<String>("title")
            let date = SQLite.Expression<Date>("date")
            let chatIdentifier = UUID()
            
            let addChatQuery = chats.insert(
                id <- chatIdentifier,
                row_title <- title,
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
    
    func getOwner() throws -> UUID {
        let guests = Table("guests")
        let id = SQLite.Expression<UUID>("id")
        let isOwner = SQLite.Expression<Bool>("isOwner")
        
        if let row = try db.pluck(guests.filter(isOwner == true)) {
            return row[id]
        } else {
            throw DBError.ownerIDNotFound
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
    
    private func fetchSingleChat(chatID: ChatID) throws -> Chat {
        
        let chatTable = Table("chats")
        let t_id = SQLite.Expression<UUID>("id")
        let t_title = SQLite.Expression<String>("title")
        let t_date = SQLite.Expression<Date>("date")
        
        guard let row = try db.pluck(chatTable.filter(t_id == chatID)) else {
            throw DBError.chatNotFound
        }
        let chat_title = row[t_title]
        let chat_id = row[t_id]
        let chat_date = row[t_date]
        let chat_guests = try fetchGuests(for: chatID)
        let chat_messages = try fetchMessages(for: chatID)
        
        return Chat(id: chat_id, title: chat_title, guests: chat_guests, messages: chat_messages, date: chat_date)
    }
    
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
    
    private func fetchGuests(for chatID: ChatID) throws -> [GuestID] {
        
        let chatGuestsTable = Table("chat_guests")
        let t_chatID = Expression<ChatID>("chatID")
        let t_guestID = Expression<GuestID>("guestID")

        let query = chatGuestsTable.filter(t_chatID == chatID).select(t_guestID)
        
        let result = try db.prepare(query).map { row in
            try row.get(t_guestID)
        }
        
        return result
    }
    
    private func fetchMessages(for chatID: ChatID) throws -> [MessageID] {
        let messagesTable = Table("messages")
        let t_chatID = Expression<ChatID>("chatID")
        let t_messageID = Expression<MessageID>("id")
        
        let query = messagesTable.filter(t_chatID == chatID)
        
        let result = try db.prepare(query).map { row in
            try row.get(t_messageID)
        }
        
        return result
    }
}

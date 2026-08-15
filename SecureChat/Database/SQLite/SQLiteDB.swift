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
    
    func addGuest(guest: Guest) {
        do {
            // Update messages table
            let addMessageQuery = GuestsTable.guests.insert(
                GuestsTable.id <- guest.id,
                GuestsTable.date <- Date(),
                GuestsTable.isOwner <- guest.isOwner,
                GuestsTable.username <- guest.username
            )
            
            try db.run(addMessageQuery)
            SCLogger.logger.info(message: "New guest record created! \(guest.username) \(guest.id)", category: .Database)

        } catch {
            SCLogger.logger.error(message: "Error creating guest record: \(guest.username) \(guest.id)", error: error, category: .Database)
        }
    }
    
    func update(guest: Guest) {
        
        do {
            // Update guest
            
            let guestRow = GuestsTable.guests.filter(GuestsTable.id == guest.id).limit(1)
            
            let addMessageQuery = guestRow.update (
                GuestsTable.date <- Date(),
                GuestsTable.isOwner <- guest.isOwner,
                GuestsTable.username <- guest.username,
                GuestsTable.isRegistered <- guest.isRegistered
            )
            
            try db.run(addMessageQuery)
            SCLogger.logger.info(message: "Guest updated correctly! \(guest.username) \(guest.id)", category: .Database)

        } catch {
            SCLogger.logger.error(message: "Error updating guest record: \(guest.username) \(guest.id)", error: error, category: .Database)
        }
    }
    
    func saveMessage(message: Message) {
        do {
            // Update messages table
            let newMessageID = UUID()
            
            let addMessageQuery = MessagesTable.messages.insert(
                MessagesTable.id <- newMessageID,
                MessagesTable.chatID <- message.chatID,
                MessagesTable.guestID <- message.guestID,
                MessagesTable.content <- message.content,
                MessagesTable.date <- message.date,
                MessagesTable.ttl <- message.ttl,
                MessagesTable.isOwner <- message.isOwner
            )
            
            try db.run(addMessageQuery)
            SCLogger.logger.info(message: "Message record created!", category: .Database)
            // the subscriber of this message notification is ChatRepository
            notificationCenter.post(Notification(name: ChatNotification.newMessage, object: message))

        } catch {
            SCLogger.logger.error(message: "Error creating message record:", error: error, category: .Database)
        }
    }
    
    func getMessage(id: MessageID) -> Message? {
        do {
            // Update messages table
            if let row = try db.pluck(MessagesTable.messages.filter(MessagesTable.id == id)) {
                return Message(id: row[MessagesTable.id], chatID: row[MessagesTable.chatID], guestID: row[MessagesTable.guestID], isOwner: row[MessagesTable.isOwner], content: row[MessagesTable.content], date: row[MessagesTable.date], ttl: row[MessagesTable.ttl])
            } else {
                SCLogger.logger.error(message: "Message not found", category: .Message)
            }
            
        } catch {
            SCLogger.logger.error(message: "Error fetching the message:", error: error, category: .Database)
        }
    
        return nil
    }
    
    func getGuest(id: GuestID) throws -> Guest {
        
        guard let row = try db.pluck(GuestsTable.guests.filter(GuestsTable.id == id)) else {
            SCLogger.logger.error(message: DBError.ownerIDNotFound.localizedDescription, category: .Database)
            throw DBError.ownerIDNotFound
        }
        
        let fetchedGuest = Guest(
            id: row[GuestsTable.id],
            username: row[GuestsTable.username],
            isOwner: row[GuestsTable.isOwner],
            date: row[GuestsTable.date],
            isRegistered: row[GuestsTable.isRegistered])
        
        return fetchedGuest
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
            let chatIdentifier = UUID()
            
            let addChatQuery = ChatsTable.chats.insert(
                ChatsTable.id <- chatIdentifier,
                ChatsTable.title <- title,
                ChatsTable.date <- Date()
            )
            
            try db.run(addChatQuery)
            
            // update chat_guests table
            let guestIdentifier = try getOwner().id
            
            let addChatGuestsQuery = ChatsGuestsTable.chatsGuests.insert (
                ChatsGuestsTable.chatID <- chatIdentifier,
                ChatsGuestsTable.guestID <- guestIdentifier
            )
            
            try db.run(addChatGuestsQuery)

            SCLogger.logger.info(message: "Chat \"\(title)\" record created!", category: .Database)
            SCLogger.logger.info(message: "ChatID: \(chatIdentifier) GuestID: \(guestIdentifier)", category: .Database)
            
            chatList = try fetchChatList()
            
        } catch {
            SCLogger.logger.error(message: "Error creating Chat \"\(title)\" record:", error: error, category: .Database)
        }
    }
    
    func getOwner() throws -> Guest {
        if let row = try db.pluck(GuestsTable.guests.filter(GuestsTable.isOwner)) {
            return Guest(id: row[GuestsTable.id], username: row[GuestsTable.username], isOwner: row[GuestsTable.isOwner], date: row[GuestsTable.date], isRegistered: row[GuestsTable.isRegistered])
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
        
        guard let row = try db.pluck(ChatsTable.chats.filter(ChatsTable.id == chatID)) else {
            throw DBError.chatNotFound
        }
        let chat_title = row[ChatsTable.title]
        let chat_id = row[ChatsTable.id]
        let chat_date = row[ChatsTable.date]
        let chat_guests = try fetchGuests(for: chatID)
        let chat_messages = try fetchMessages(for: chatID)
        
        return Chat(id: chat_id, title: chat_title, guests: chat_guests, messages: chat_messages, date: chat_date)
    }
    
    private func fetchChatList() throws -> [ChatListModel] {
    
        var result: [ChatListModel] = []
        
        for chat in try db.prepare(ChatsTable.chats) {
            let chatList = ChatListModel(chatID: chat[ChatsTable.id], title: chat[ChatsTable.title], date: chat[ChatsTable.date])
            result.append(chatList)
        }
        
        return result
    }
    
    private func fetchGuests(for chatID: ChatID) throws -> [GuestID] {
        
        let chatGuestsTable = Table("chat_guests")
        let t_chatID = Expression<ChatID>("chatID")
        let t_guestID = Expression<GuestID>("guestID")

        let query = ChatsGuestsTable.chatsGuests.filter(ChatsGuestsTable.chatID == chatID).select(ChatsGuestsTable.guestID)
        
        let result = try db.prepare(query).map { row in
            try row.get(t_guestID)
        }
        
        return result
    }
    
    private func fetchMessages(for chatID: ChatID) throws -> [MessageID] {
        let messagesTable = Table("messages")
        let t_chatID = Expression<ChatID>("chatID")
        let t_messageID = Expression<MessageID>("id")
        
        let query = MessagesTable.messages.filter(MessagesTable.chatID == chatID)
        
        let result = try db.prepare(query).map { row in
            try row.get(MessagesTable.id)
        }
        
        return result
    }
}

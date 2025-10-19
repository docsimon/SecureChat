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
    }

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
            SCLogger.logger.info(message: LogMessage.SQLiteTableCreated, category: .Database)
        } catch {
            SCLogger.logger.error(message: LogMessage.SQLiteTableError, error: error, category: .Database)
        }
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
    
    var chatList: [ChatListModel] = []
}

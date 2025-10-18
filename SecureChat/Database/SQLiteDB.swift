//
// SQLiteDB.swift
// SecureChat  
//
// Created by Simone Barbara on 18/10/2025.                               
// All Rights Reserved.                                                         

import SQLite
import Foundation

final class SQLiteDB: DatabaseStrategy {
    
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
        // Create/Connect DB
        let db = try Connection(path)
        
        // Check tables
        
        
        
    }
    
    var chatList: [ChatListModel] = []
    
    private let db: Connection
    private let path: String
    
    init(path: String = GlobalState.sqlPath) throws {
        self.path = path
        self.db = try SQLiteDB.createDB(with: path)
    }

    private static func createDB(with path: String) throws -> Connection {
            let db = try Connection("\(path)/SCdb.sqlite3")
            //db?.busyTimeout = 5
            return db
    }
    // Checks if all the tables already exist. If not (for example there is partial number of tables)
    // means that there the db is inconsistent and should be reset.
    private func shouldCreateTables(db: Connection) -> Bool {
        do {
            let guestsExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='guests';") as? Int64 ?? 0
            let chatsExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='chats';") as? Int64 ?? 0
            let messagesExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='messages';") as? Int64 ?? 0
            
            let sum = guestsExists + chatsExists + messagesExists
            if sum == 0 || sum != GlobalState.numbersOfTables {
                return true
            }
           
            return true
            
        } catch {
            SCLogger.logger.error(message: LogMessage.errorTables, category: .Database)
        }
        return false
        
    }
    
    private func removeDB() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let sqliteFileURL = documentsURL.appendingPathComponent("SCdb.sqlite3")
        do {
            try fileManager.removeItem(at: sqliteFileURL)
            SCLogger.logger.info(message: LogMessage.dbDeleted, category: .Database)
        } catch {
            SCLogger.logger.error(message: LogMessage.dbNotDeleted, error: error, category: .Database)
        }
    }
    
    private func createTablesIfNeeded(db: Connection) {
        if shouldCreateTables(db: db) {
            removeDB()
            createTables()
        }
    }
    
    private func createTables() {
        
    }
    
    private func createGuestTable(db: Connection) throws {
        
        // Check if table guests exists, otherwise return
        let tableExists = try db.scalar("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='guests';") as? Int64 ?? 0
        
        guard tableExists == 0 else {
            return
        }

        
        let guests = Table("guests")
            let id = SQLite.Expression<UUID>("id")
            let username = SQLite.Expression<String>("name")

            try db.run(guests.create { t in
                t.column(id, primaryKey: true)
                t.column(username)
        
            })
            // CREATE TABLE "users" (
            //     "id" UUID PRIMARY KEY NOT NULL,
            //     "username" TEXT,
            // )
        
    }
}

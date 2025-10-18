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
    
    var chatList: [ChatListModel] = []
    
    private let db: Connection
    
    init(path: String = GlobalState.sqlPath) throws {
        self.db = try SQLiteDB.createDB(with: path)
    }

    private static func createDB(with path: String) throws -> Connection {
            let db = try Connection("\(path)/db.sqlite3")
            //db?.busyTimeout = 5
            return db
    }
}

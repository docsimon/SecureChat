//
// SQLiteConstants.swift
// SecureChat  
//
// Created by Simone Barbara on 19/10/2025.                               
// All Rights Reserved.                                                         


import Foundation

struct SQLiteConstants {
    // Inside Documents. Joining with `+` dropped the separator and put the
    // file next to Documents, in the container root: writable in the
    // Simulator, refused on a phone.
    static let sqlPath = URL.documentsDirectory.appending(path: SQLiteConstants.dbName).path(percentEncoded: false)
    // Number of tables (guests, chats, messages)
    static let numbersOfTables = 3
    private static let dbName = "SCdb.sqlite3"
    
    private init() {}
}

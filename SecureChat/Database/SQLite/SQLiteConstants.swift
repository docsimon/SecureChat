//
// SQLiteConstants.swift
// SecureChat  
//
// Created by Simone Barbara on 19/10/2025.                               
// All Rights Reserved.                                                         


import Foundation

struct SQLiteConstants {
    static let sqlPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first! + SQLiteConstants.dbName
    // Number of tables (guests, chats, messages)
    static let numbersOfTables = 3
    private static let dbName = "SCdb.sqlite3"
    
    private init() {}
}

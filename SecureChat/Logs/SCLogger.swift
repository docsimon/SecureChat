//
// SCLogger.swift
// SecureChat
//
// Created by Simone Barbara on 18/10/2025.                               
// All Rights Reserved.                                                         

import os.log
import Foundation

final class SCLogger {
    static let logger = SCLogger()
    
    private let osLogger = Logger(subsystem: "simone.app.dev.SecureChat", category: "app")
    
    func debug(message: String, category: LogCategory) {
            #if DEBUG
            osLogger.debug("[\(category.rawValue)] \(message)")
            #endif
        }

        func info(message: String, category: LogCategory) {
            osLogger.info("[INFO] [\(category.rawValue)] \(message)")
        }

        func error(message: String, error: Error? = nil, category: LogCategory) {
            osLogger.error("[ERROR] [\(category.rawValue)] \(message) \(error)")
        }
}

enum LogCategory: String {
    case Database = "Database"
    case Network = "Network"
    case Message = "Message"
}

struct LogMessage {
    static let infoDB = "Database created correctly"
    static let errorDB = "Failed to create the Database"
    static let errorTables = "Number of tables doesn't match the required number. DB inconsistent"
    static let dbDeleted = "Database deleted"
    static let dbNotDeleted = "Database NOT deleted!!!"
    static let SQLiteTableCreated = "SQLite tables have been created!"
    static let SQLiteTableError = "Error while creating SQLite tables"
    static let SQLiteDBCreated = "SQLite DB created!"
    static let SQLiteDBNotCreated = "Error creating SQLite DB!"
    // Websocket
    static let WebSocketDisconnected = "WebSocket disconnetted!"
}

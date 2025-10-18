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
            osLogger.info("[\(category.rawValue)] \(message)")
        }

        func error(message: String, error: Error? = nil, category: LogCategory) {
            osLogger.error("[\(category.rawValue)] \(message) \(error)")
        }
}

enum LogCategory: String {
    case Database = "Database"
    case Network = "Network"
}

struct LogMessage {
    static let infoDB = "Database created correctly"
    static let errorDB = "Failed to create the Database"
}

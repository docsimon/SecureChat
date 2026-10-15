//
//  DatabaseLocation.swift
//  SecureChat
//
//  Where the database lives, and how the OS guards it
//  (architecture-decisions.md, "Local storage"; session-workflow.md,
//  "Message storage"): in Application Support, never in a backup, and
//  unreadable while the phone is locked. The directory carries the
//  protection class, so the files SQLite creates beside the database
//  (journals) get it too. Encrypting the messages themselves is the next
//  step; this is only the OS layer.
//

import Foundation

enum DatabaseLocation {

    static let fileName = "SCdb.sqlite3"

    /// Prepares the directory and returns the database path. Moves a
    /// database left in Documents by an earlier build, so pairings survive.
    static func prepare(in directory: URL = URL.applicationSupportDirectory.appending(path: "Database"),
                        legacyDirectory: URL? = URL.documentsDirectory,
                        fileManager: FileManager = .default) throws -> String {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
        // Also for a directory created by an earlier run.
        try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        var resource = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try resource.setResourceValues(values)

        let database = directory.appending(path: fileName)
        if let legacyDirectory {
            try moveLegacyFiles(from: legacyDirectory, to: directory, fileManager: fileManager)
        }
        if fileManager.fileExists(atPath: database.path) {
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: database.path)
        }
        return database.path(percentEncoded: false)
    }

    private static func moveLegacyFiles(from legacy: URL, to directory: URL, fileManager: FileManager) throws {
        let legacyDatabase = legacy.appending(path: fileName)
        guard fileManager.fileExists(atPath: legacyDatabase.path),
              !fileManager.fileExists(atPath: directory.appending(path: fileName).path) else { return }
        for suffix in ["", "-journal", "-wal", "-shm"] {
            let source = legacy.appending(path: fileName + suffix)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            try fileManager.moveItem(at: source, to: directory.appending(path: fileName + suffix))
        }
        SCLogger.logger.info(message: "Database moved out of Documents", category: .Database)
    }
}

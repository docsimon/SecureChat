//
// SQLiteConstants.swift
// SecureChat
//
// Created by Simone Barbara on 19/10/2025.
// All Rights Reserved.


import Foundation

struct SQLiteConstants {
    /// The placeholder chat stack's tables, from before sessions. Their rows
    /// were test data. Found by `guests`, which only that stack had; its
    /// `messages` table had other columns, so it goes too.
    static let placeholderMarkerTable = "guests"
    static let placeholderTables = ["chats_guests", "messages", "chats", "guests"]

    private init() {}
}

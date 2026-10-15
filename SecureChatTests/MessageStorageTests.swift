//
//  MessageStorageTests.swift
//  SecureChatTests
//
//  Where messages are kept and how: the database file's location and OS
//  protection, the message table, and the store the chat screen reads.
//

import XCTest
import SQLite
import PairingKit
@testable import SecureChat

@MainActor
final class MessageStorageTests: XCTestCase {

    private var directory: URL!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MessageStorageTests-\(UUID().uuidString)")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: Location

    func test_location_isExcludedFromBackup_andProtectedUntilUnlocked() throws {
        let path = try DatabaseLocation.prepare(in: directory.appending(path: "Database"), legacyDirectory: nil)
        _ = try SQLiteDB(path: path)

        let folder = URL(filePath: path).deletingLastPathComponent()
        XCTAssertEqual(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        // The Simulator's file system has no Data Protection: the attribute
        // reads back nil there, so this half is checked on a phone only.
#if !targetEnvironment(simulator)
        let protection = try FileManager.default.attributesOfItem(atPath: folder.path)[.protectionKey] as? FileProtectionType
        XCTAssertEqual(protection, .complete)
#endif
    }

    func test_location_movesTheDatabaseOutOfDocuments_keepingItsContacts() throws {
        let legacy = directory.appending(path: "Documents")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        let ada = PairedContact(identityPublicKey: Data(repeating: 7, count: 32), accountUUID: UUID(),
                                displayName: "Ada", pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try SQLiteDB(path: legacy.appending(path: DatabaseLocation.fileName).path).addContact(ada)

        let path = try DatabaseLocation.prepare(in: directory.appending(path: "Database"), legacyDirectory: legacy)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.appending(path: DatabaseLocation.fileName).path))
        XCTAssertEqual(try SQLiteDB(path: path).fetchContacts(), [ada])
    }

    // MARK: Schema

    func test_placeholderChatTables_areDropped_contactsAreKept() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "old.sqlite3").path
        let old = try Connection(path)
        try old.run("CREATE TABLE guests (id TEXT)")
        try old.run("CREATE TABLE chats (id TEXT)")
        try old.run("CREATE TABLE chats_guests (chatID TEXT, guestID TEXT)")
        try old.run("CREATE TABLE messages (id TEXT, chatID TEXT, guestID TEXT, content TEXT)")
        try SQLiteSchema().createContactsTable(db: old)
        let ada = PairedContact(identityPublicKey: Data(repeating: 7, count: 32), accountUUID: UUID(),
                                displayName: "Ada", pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
        try old.run(ContactsTable.contacts.insert(
            ContactsTable.identityPublicKey <- ada.identityPublicKey, ContactsTable.accountUUID <- ada.accountUUID,
            ContactsTable.displayName <- ada.displayName, ContactsTable.pairedAt <- ada.pairedAt))

        let db = try SQLiteDB(path: path)

        XCTAssertFalse(try old.tableExists("guests"))
        XCTAssertFalse(try old.tableExists("chats"))
        XCTAssertEqual(try db.fetchContacts(), [ada])
        let message = StoredMessage(peer: ada.accountUUID, text: "hi", status: .sent)
        try db.addMessage(message)
        XCTAssertEqual(try db.fetchMessages().map(\.id), [message.id])
    }

    // MARK: Store

    func test_messages_surviveReopening_withTheirStatus() throws {
        let db = try SQLiteDB(path: ":memory:")
        let ada = UUID(), bob = UUID()
        let store = MessageStore(db: db)
        store.add(StoredMessage(peer: ada, text: "one", date: Date(timeIntervalSince1970: 1), status: .received))
        store.add(StoredMessage(peer: ada, text: "two", date: Date(timeIntervalSince1970: 2), status: .waiting))
        store.add(StoredMessage(peer: bob, text: "other", date: Date(timeIntervalSince1970: 3), status: .waiting))

        store.resolveWaiting(with: ada, as: .sent)

        let reopened = MessageStore(db: db)
        XCTAssertEqual(reopened.messages(with: ada).map(\.text), ["one", "two"])
        XCTAssertEqual(reopened.messages(with: ada).map(\.status), [.received, .sent])
        XCTAssertEqual(reopened.messages(with: bob).map(\.status), [.waiting], "another chat's message is untouched")
    }

    func test_resolveAllWaiting_onlyTouchesWaitingMessages() throws {
        let store = MessageStore(db: try SQLiteDB(path: ":memory:"))
        let ada = UUID(), bob = UUID()
        store.add(StoredMessage(peer: ada, text: "sent", status: .sent))
        store.add(StoredMessage(peer: ada, text: "waiting", status: .waiting))
        store.add(StoredMessage(peer: bob, text: "waiting", status: .waiting))

        store.resolveAllWaiting(as: .notDelivered)

        XCTAssertEqual(store.messages(with: ada).map(\.status), [.sent, .notDelivered])
        XCTAssertEqual(store.messages(with: bob).map(\.status), [.notDelivered])
    }
}

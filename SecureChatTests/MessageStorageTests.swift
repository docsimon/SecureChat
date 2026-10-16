//
//  MessageStorageTests.swift
//  SecureChatTests
//
//  Where messages are kept and how: the database file's location and OS
//  protection (option A), the message table, and the store the chat screen
//  reads, which seals every text with its contact's key (option B).
//

import XCTest
import SQLite
import CryptoKit
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
        let message = SealedMessage(id: UUID(), peer: ada.accountUUID, sealedText: Data([1, 2, 3]),
                                    date: Date(timeIntervalSince1970: 1_800_000_000), status: .sent)
        try db.addMessage(message)
        XCTAssertEqual(try db.fetchMessages(), [message])
    }

    // MARK: Store

    func test_messages_surviveReopening_withTheirStatus() throws {
        let db = try SQLiteDB(path: ":memory:"), keys = MessageKeyStore.inMemory()
        let ada = UUID(), bob = UUID()
        let store = MessageStore(db: db, keys: keys, keepKeysFor: [])
        store.add(StoredMessage(peer: ada, text: "one", date: Date(timeIntervalSince1970: 1), status: .received))
        store.add(StoredMessage(peer: ada, text: "two", date: Date(timeIntervalSince1970: 2), status: .waiting))
        store.add(StoredMessage(peer: bob, text: "other", date: Date(timeIntervalSince1970: 3), status: .waiting))

        store.resolveWaiting(with: ada, as: .sent)

        let reopened = MessageStore(db: db, keys: keys, keepKeysFor: [])
        XCTAssertEqual(reopened.messages(with: ada).map(\.text), ["one", "two"])
        XCTAssertEqual(reopened.messages(with: ada).map(\.status), [.received, .sent])
        XCTAssertEqual(reopened.messages(with: bob).map(\.status), [.waiting], "another chat's message is untouched")
    }

    func test_resolveAllWaiting_onlyTouchesWaitingMessages() throws {
        let store = MessageStore(db: try SQLiteDB(path: ":memory:"), keys: .inMemory(), keepKeysFor: [])
        let ada = UUID(), bob = UUID()
        store.add(StoredMessage(peer: ada, text: "sent", status: .sent))
        store.add(StoredMessage(peer: ada, text: "waiting", status: .waiting))
        store.add(StoredMessage(peer: bob, text: "waiting", status: .waiting))

        store.resolveAllWaiting(as: .notDelivered)

        XCTAssertEqual(store.messages(with: ada).map(\.status), [.sent, .notDelivered])
        XCTAssertEqual(store.messages(with: bob).map(\.status), [.notDelivered])
    }

    // MARK: Sealing (option B)

    private func fileBytes(_ path: String) -> Data {
        let fm = FileManager.default
        return ["", "-journal", "-wal"].reduce(Data()) { data, suffix in
            data + (fm.contents(atPath: path + suffix) ?? Data())
        }
    }

    func test_theDatabaseFileNeverHoldsTheText() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "sealed.sqlite3").path
        let store = MessageStore(db: try SQLiteDB(path: path), keys: .inMemory(), keepKeysFor: [])
        let ada = UUID()

        store.add(StoredMessage(peer: ada, text: "meet at the old bridge at nine", status: .sent))

        XCTAssertNil(fileBytes(path).range(of: Data("old bridge".utf8)))
        XCTAssertEqual(store.messages(with: ada).map(\.text), ["meet at the old bridge at nine"])
    }

    func test_deletingAChat_shredsItsKey_andOnlyThatChat() throws {
        let db = try SQLiteDB(path: ":memory:"), keys = MessageKeyStore.inMemory()
        let ada = UUID(), bob = UUID()
        let store = MessageStore(db: db, keys: keys, keepKeysFor: [ada, bob])
        store.add(StoredMessage(peer: ada, text: "for Ada", status: .sent))
        store.add(StoredMessage(peer: bob, text: "for Bob", status: .sent))
        let adaRow = try XCTUnwrap(try db.fetchMessages().first { $0.peer == ada })

        try store.deleteMessages(with: ada)

        XCTAssertNil(try keys.existingKey(for: ada), "the key goes first")
        XCTAssertTrue(store.messages(with: ada).isEmpty)
        XCTAssertEqual(try db.fetchMessages().map(\.peer), [bob])
        // A copy of the row left somewhere on disk is now unreadable: the
        // only key that opened it is gone, and a new key is a different one.
        let newKey = try keys.key(for: ada)
        XCTAssertThrowsError(try MessageSeal.open(adaRow.sealedText, id: adaRow.id, peer: ada, key: newKey))
        XCTAssertEqual(MessageStore(db: db, keys: keys, keepKeysFor: [ada, bob]).messages(with: bob).map(\.text),
                       ["for Bob"])
    }

    func test_aRowWhoseKeyIsGone_orMovedToAnotherMessage_isShownAsUnreadable() throws {
        let db = try SQLiteDB(path: ":memory:"), keys = MessageKeyStore.inMemory()
        let ada = UUID(), bob = UUID()
        let store = MessageStore(db: db, keys: keys, keepKeysFor: [ada, bob])
        store.add(StoredMessage(peer: ada, text: "first", status: .sent))
        let first = try XCTUnwrap(try db.fetchMessages().first)
        // The same sealed bytes under another id: must not open.
        try db.addMessage(SealedMessage(id: UUID(), peer: ada, sealedText: first.sealedText,
                                        date: first.date.addingTimeInterval(1), status: .sent))
        store.add(StoredMessage(peer: bob, text: "for Bob", status: .sent))
        try keys.delete(for: bob)

        let reopened = MessageStore(db: db, keys: keys, keepKeysFor: [ada, bob])

        XCTAssertEqual(reopened.messages(with: ada).map(\.text), ["first", StoredMessage.unreadableText])
        XCTAssertEqual(reopened.messages(with: bob).map(\.text), [StoredMessage.unreadableText])
    }

    func test_plainTextFromAnEarlierBuild_isSealed_andLeavesNothingInTheFile() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appending(path: "earlier.sqlite3").path
        let ada = UUID()
        // The option A schema: a `messages` table with the text in the clear.
        let earlier = try Connection(path)
        try earlier.run("CREATE TABLE messages (id TEXT PRIMARY KEY NOT NULL, peer TEXT NOT NULL, text TEXT NOT NULL, date TEXT NOT NULL, status INTEGER NOT NULL)")
        try earlier.run("CREATE INDEX index_messages_on_peer_date ON messages (peer, date)")
        let old = Table("messages")
        try earlier.run(old.insert(MessagesTable.id <- UUID(), MessagesTable.peer <- ada,
                                   SQLite.Expression<String>("text") <- "the old secret",
                                   MessagesTable.date <- Date(timeIntervalSince1970: 1),
                                   MessagesTable.status <- StoredMessage.Status.received.rawValue))
        XCTAssertNotNil(fileBytes(path).range(of: Data("old secret".utf8)), "precondition: plain on disk")

        let store = MessageStore(db: try SQLiteDB(path: path), keys: .inMemory(), keepKeysFor: [ada])

        XCTAssertEqual(store.messages(with: ada).map(\.text), ["the old secret"])
        XCTAssertEqual(store.messages(with: ada).map(\.status), [.received])
        XCTAssertFalse(try earlier.tableExists(PlaintextMessagesTable.name))
        XCTAssertNil(fileBytes(path).range(of: Data("old secret".utf8)), "no plaintext left in any page")
    }

    func test_keysOfPeopleNoLongerHere_areDeleted_atLaunch() throws {
        let keys = MessageKeyStore.inMemory()
        let ada = UUID(), gone = UUID()
        _ = try keys.key(for: ada)
        _ = try keys.key(for: gone)

        _ = MessageStore(db: try SQLiteDB(path: ":memory:"), keys: keys, keepKeysFor: [ada])

        XCTAssertNotNil(try keys.existingKey(for: ada))
        XCTAssertNil(try keys.existingKey(for: gone))
    }

    /// The real Keychain, under a throwaway service. Simulator only: a phone
    /// runs these tests too, and its Keychain holds real keys.
    func test_liveKeychain_storesReadsAndDeletesPerContact() throws {
#if !targetEnvironment(simulator)
        throw XCTSkip("Keychain test runs in the Simulator only")
#else
        let keys = MessageKeyStore(keychainService: "chat.securechat.tests.\(UUID().uuidString)")
        let ada = UUID(), bob = UUID()
        defer { try? keys.deleteAll(except: []) }

        let adaKey = try keys.key(for: ada)
        _ = try keys.key(for: bob)

        XCTAssertEqual(try keys.key(for: ada).withUnsafeBytes { Data($0) }, adaKey.withUnsafeBytes { Data($0) },
                       "created once, then read back")
        try keys.deleteAll(except: [bob])
        XCTAssertNil(try keys.existingKey(for: ada))
        XCTAssertNotNil(try keys.existingKey(for: bob))
        try keys.delete(for: bob)
        XCTAssertNil(try keys.existingKey(for: bob))
#endif
    }
}

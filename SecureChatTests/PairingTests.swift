//
//  PairingTests.swift
//  SecureChatTests
//
//  The app's side of pairing: contact storage, the local identity, and the
//  "Add contact" view model. The pairing rules themselves are tested in
//  PairingKit. Nothing here reaches Apple, a server, or the Keychain.
//

import XCTest
import PairingKit
@testable import SecureChat

@MainActor
final class PairingTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "PairingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func contact(_ byte: UInt8, name: String = "Ada") -> PairedContact {
        PairedContact(identityPublicKey: Data(repeating: byte, count: 32), accountUUID: UUID(),
                      displayName: name, pairedAt: Date(timeIntervalSince1970: 1_800_000_000))
    }

    /// A code as another phone would show it.
    private func code(_ byte: UInt8, name: String = "Bob", acknowledging peer: Data? = nil,
                      uuid: UUID = UUID()) throws -> String {
        try PairingPayload(identityPublicKey: Data(repeating: byte, count: 32), accountUUID: uuid,
                           displayName: name, acknowledging: peer).encoded()
    }

    private func makeViewModel(name: String? = "Ada",
                               identity: @escaping () throws -> LocalIdentity = {
                                   LocalIdentity(identityPublicKey: Data(repeating: 1, count: 32), accountUUID: UUID())
                               },
                               db: DatabaseStrategy? = nil) throws
        -> (PairingViewModel, ContactRepository) {
        let profile = ProfileStore(defaults: defaults)
        profile.displayName = name
        let repository = ContactRepository(db: try db ?? SQLiteDB(path: ":memory:"))
        let viewModel = PairingViewModel(identity: identity, contacts: repository, profile: profile)
        return (viewModel, repository)
    }

    // MARK: Storage

    func test_contacts_surviveReopeningTheStore() throws {
        let db = try SQLiteDB(path: ":memory:")
        let ada = contact(7, name: "Ada"), bob = contact(8, name: "Bob 🦦")
        try ContactRepository(db: db).add(ada)
        try ContactRepository(db: db).add(bob)

        XCTAssertEqual(ContactRepository(db: db).contacts, [ada, bob])
    }

    func test_contacts_refuseASecondRecordForTheSameKeyOrAccount() throws {
        let repository = ContactRepository(db: try SQLiteDB(path: ":memory:"))
        let ada = contact(7)
        try repository.add(ada)

        XCTAssertThrowsError(try repository.add(PairedContact(
            identityPublicKey: ada.identityPublicKey, accountUUID: UUID(), displayName: "x", pairedAt: Date())))
        XCTAssertThrowsError(try repository.add(PairedContact(
            identityPublicKey: Data(repeating: 9, count: 32), accountUUID: ada.accountUUID, displayName: "x", pairedAt: Date())))
        XCTAssertEqual(repository.contacts, [ada])
    }

    // MARK: Identity

    func test_debugIdentity_isCreatedOnceAndThenReused() {
        let first = DebugLocalIdentity.loadOrCreate(defaults: defaults)
        let second = DebugLocalIdentity.loadOrCreate(defaults: defaults)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.identityPublicKey.count, 32)
    }

    func test_debugIdentity_givesSessionsThePrivateKeyOfThePairedPublicKey() {
        let paired = DebugLocalIdentity.loadOrCreate(defaults: defaults)
        let session = DebugLocalIdentity.loadOrCreateForSessions(defaults: defaults)

        XCTAssertEqual(session.privateKey.publicKey.rawRepresentation, paired.identityPublicKey)
        XCTAssertEqual(session.accountUUID, paired.accountUUID)
    }

    // MARK: View model

    func test_withoutAName_asksForOne_thenPairs() throws {
        let (viewModel, _) = try makeViewModel(name: nil)
        guard case .needsName = viewModel.phase else { return XCTFail("expected needsName") }
        XCTAssertFalse(viewModel.canConfirmName)

        viewModel.draftName = "  Ada \n"
        XCTAssertTrue(viewModel.canConfirmName)
        viewModel.confirmName()

        guard case .pairing(let pairing) = viewModel.phase else { return XCTFail("expected pairing") }
        XCTAssertEqual(ProfileStore(defaults: defaults).displayName, "Ada")
        XCTAssertEqual(try PairingPayload(scanned: XCTUnwrap(pairing.codeToShow)).displayName, "Ada")
    }

    func test_unregisteredDevice_cannotPair() throws {
        let (viewModel, _) = try makeViewModel(identity: { throw LocalIdentityError.notRegistered })
        guard case .unavailable = viewModel.phase else { return XCTFail("expected unavailable") }
    }

    func test_scanningTheirCode_storesTheContact_andCompletesWhenTheyHaveOurs() throws {
        let ownKey = Data(repeating: 1, count: 32)
        let (viewModel, repository) = try makeViewModel(
            identity: { LocalIdentity(identityPublicKey: ownKey, accountUUID: UUID()) })
        let bobUUID = UUID()

        let first = viewModel.scanned(try code(2, uuid: bobUUID))
        XCTAssertEqual(repository.contacts.map(\.displayName), ["Bob"])
        guard case .pairing(let pairing) = viewModel.phase else { return XCTFail("expected pairing") }
        // Our code now tells Bob's phone that we have his.
        XCTAssertTrue(try PairingPayload(scanned: XCTUnwrap(pairing.codeToShow))
            .acknowledges(Data(repeating: 2, count: 32)))

        let second = viewModel.scanned(try code(2, acknowledging: ownKey, uuid: bobUUID))
        let bob = try XCTUnwrap(repository.contacts.first)
        XCTAssertEqual(repository.contacts.count, 1)
        XCTAssertEqual(pairing.progress, .bothWays(bob))
        XCTAssertEqual([first, second], [.readTheirs(bob), .completed(bob)])
    }

    func test_aRefusedCode_isSignalled_andStoresNothing() throws {
        let (viewModel, repository) = try makeViewModel()

        let event = viewModel.scanned("https://example.com")

        XCTAssertEqual(event, .refused(.notAPairingCode))
        XCTAssertTrue(repository.contacts.isEmpty)
    }

    func test_whenTheContactCannotBeSaved_pairingStops_withoutASuccessSignal() throws {
        let (viewModel, repository) = try makeViewModel(db: FailingContactsDB())

        let event = viewModel.scanned(try code(2))

        guard case .unavailable = viewModel.phase else { return XCTFail("expected unavailable") }
        XCTAssertTrue(repository.contacts.isEmpty)
        XCTAssertNil(event, "nothing to signal when the contact was not saved")
    }
}

/// Reads no contacts and cannot save one. Nothing else is reachable from
/// the pairing code under test.
private struct FailingContactsDB: DatabaseStrategy {
    struct Failure: Error {}
    func fetchContacts() throws -> [PairedContact] { [] }
    func addContact(_ contact: PairedContact) throws { throw Failure() }

    func fetchMessages() throws -> [SealedMessage] { [] }
    func addMessage(_ message: SealedMessage) throws {}
    func addMessages(_ messages: [SealedMessage]) throws {}
    func updateStatus(of ids: [UUID], to status: StoredMessage.Status) throws {}
    func deleteMessages(with peer: UUID) throws {}
    func plaintextMessages() throws -> [StoredMessage] { [] }
    func dropPlaintextMessages() throws {}
}

//
//  SessionHarnessModel.swift
//  SessionTestApp
//
//  HARNESS-ONLY state: a throwaway identity in UserDefaults (the private key
//  is kept here, unlike PairingTestApp, because sessions need it), contacts
//  added by pasting a pairing code or face to face (to pair with SecureChat
//  on another phone), and the SessionService that SecureChat uses too.
//

import Foundation
import CryptoKit
import PairingKit
import SessionKit

// ObservableObject, not @Observable: this target runs on iOS 16.
final class SessionHarnessModel: ObservableObject {

    struct Message: Identifiable, Equatable {
        let id = UUID()
        let mine: Bool
        let text: String
    }

    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
        let isError: Bool
    }

    let identity: Curve25519.KeyAgreement.PrivateKey
    let accountUUID: UUID
    @Published var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.name) }
    }
    @Published var relayURL: String {
        didSet { defaults.set(relayURL, forKey: Keys.relayURL) }
    }
    @Published private(set) var contacts: [PairedContact]
    @Published private(set) var messages: [UUID: [Message]] = [:]
    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var service: SessionService?

    private let defaults: UserDefaults

    private enum Keys {
        static let key = "sessionharness.identityPrivateKey"
        static let uuid = "sessionharness.accountUUID"
        static let name = "sessionharness.displayName"
        static let contacts = "sessionharness.contacts"
        static let relayURL = "sessionharness.relayURL"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.data(forKey: Keys.key),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw),
           let uuid = defaults.string(forKey: Keys.uuid).flatMap(UUID.init(uuidString:)) {
            identity = key
            accountUUID = uuid
        } else {
            identity = Curve25519.KeyAgreement.PrivateKey()
            accountUUID = UUID()
            defaults.set(identity.rawRepresentation, forKey: Keys.key)
            defaults.set(accountUUID.uuidString, forKey: Keys.uuid)
        }
        displayName = defaults.string(forKey: Keys.name) ?? "Harness \(Int.random(in: 1000...9999))"
        relayURL = defaults.string(forKey: Keys.relayURL) ?? Self.defaultRelayURL
        contacts = defaults.data(forKey: Keys.contacts)
            .flatMap { try? JSONDecoder().decode([PairedContact].self, from: $0) } ?? []
    }

    /// A Simulator reaches the Mac as localhost; a phone needs the Mac's LAN
    /// address (the same one AuthServerConfig uses).
    static var defaultRelayURL: String {
        #if targetEnvironment(simulator)
        return "ws://localhost:8081/relay"
        #else
        return "ws://192.168.0.84:8081/relay"
        #endif
    }

    /// Empty while the name is not usable (blank, or only control characters).
    var pairingCode: String {
        (try? PairingPayload(identityPublicKey: identity.publicKey.rawRepresentation, accountUUID: accountUUID,
                             displayName: displayName, acknowledging: nil).encoded()) ?? ""
    }

    var fingerprint: String { Self.fingerprint(identity.publicKey.rawRepresentation) }

    static func fingerprint(_ key: Data) -> String {
        key.prefix(6).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    // MARK: Contacts

    func addContact(code: String) {
        do {
            let evaluation = try Pairing.evaluate(scanned: code.trimmingCharacters(in: .whitespacesAndNewlines),
                                                  ownIdentityPublicKey: identity.publicKey.rawRepresentation,
                                                  ownAccountUUID: accountUUID, contacts: contacts)
            if case .newContact = evaluation.outcome {
                contacts.append(evaluation.contact)
                saveContacts()
                record("Added \(evaluation.contact.displayName)")
            } else {
                record("Already a contact: \(evaluation.contact.displayName)")
            }
        } catch {
            record("Code refused: \(error)", isError: true)
        }
    }

    /// For `FaceToFacePairing`, which decides for itself what is new.
    func add(_ contact: PairedContact) {
        contacts.append(contact)
        saveContacts()
        record("Added \(contact.displayName) face to face")
    }

    func scannerFailed(_ failure: QRCodeScannerView.Failure) {
        switch failure {
        case .cameraUnavailable:
            record("No camera here (the Simulator has none). Paste a code instead.", isError: true)
        case .accessDenied:
            record("Camera access denied. Allow it in Settings, or paste a code.", isError: true)
        }
    }

    func removeAllContacts() {
        contacts = []
        saveContacts()
    }

    private func saveContacts() {
        defaults.set(try? JSONEncoder().encode(contacts), forKey: Keys.contacts)
    }

    // MARK: Relay and sessions

    func connect() {
        guard let url = URL(string: relayURL) else {
            return record("Not a URL: \(relayURL)", isError: true)
        }
        service?.disconnect()
        let service = SessionService(
            relayURL: url,
            credential: .developmentAccount(accountUUID),
            localIdentity: identity,
            localAccount: accountUUID,
            contactKey: { [weak self] account in
                self?.contacts.first { $0.accountUUID == account }?.identityPublicKey
            })
        service.onEvent = { [weak self] event in self?.handle(event) }
        self.service = service
        service.connect()
        record("Connecting to \(url.absoluteString)")
    }

    func disconnect() {
        service?.disconnect()
        record("Disconnected")
    }

    func open(_ contact: PairedContact) {
        do {
            try service?.open(contact.accountUUID)
        } catch {
            record("Can't open a session with \(contact.displayName): \(error)", isError: true)
        }
    }

    func send(_ text: String, to contact: PairedContact) {
        do {
            guard let service else { throw RelayClientError.notConnected }
            try service.send(text, to: contact.accountUUID)
            messages[contact.accountUUID, default: []].append(Message(mine: true, text: text))
        } catch {
            record("Not sent: \(error)", isError: true)
        }
    }

    private func handle(_ event: SessionService.Event) {
        switch event {
        case .established(let peer):
            record("Session open with \(name(peer))")
        case .received(let peer, .text(let text)):
            messages[peer, default: []].append(Message(mine: false, text: text))
        case .peerUnavailable(let peer, let dropped):
            record("\(name(peer)) is offline" + (dropped.isEmpty ? "" : "; \(dropped.count) message(s) not delivered"),
                   isError: true)
        case .refused(let peer, let refusal):
            record("Refused a session from \(contacts.contains { $0.accountUUID == peer } ? name(peer) : "a stranger"): \(refusal)",
                   isError: true)
        case .unanswered(let peer, let dropped):
            record("\(name(peer)) did not answer (do they have this harness as a contact?)"
                   + (dropped.isEmpty ? "" : "; \(dropped.count) message(s) not delivered"), isError: true)
        case .ended(let peer):
            record("Session with \(name(peer)) ended (a message failed to decrypt)", isError: true)
        }
    }

    private func name(_ account: UUID) -> String {
        contacts.first { $0.accountUUID == account }?.displayName ?? "unknown"
    }

    func record(_ text: String, isError: Bool = false) {
        log.insert(LogEntry(text: text, isError: isError), at: 0)
    }
}

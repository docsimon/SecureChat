//
//  PairingHarnessModel.swift
//  PairingTestApp
//
//  HARNESS-ONLY state. The identity here is a throwaway: a random X25519
//  public key (the private half is discarded — nothing in pairing uses it)
//  and a random account id, kept in UserDefaults. It never comes from
//  RegistrationKit, so this app cannot reach App Attest or the Auth Server.
//  The real app passes its registered identity to the same PairingKit calls.
//

import Foundation
import CryptoKit
import Observation
import PairingKit

@Observable
final class PairingHarnessModel {

    struct LogEntry: Identifiable {
        let id = UUID()
        let date = Date()
        let text: String
        let isError: Bool
    }

    private(set) var identityPublicKey: Data
    private(set) var accountUUID: UUID
    var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.name) }
    }
    private(set) var contacts: [PairedContact]
    private(set) var log: [LogEntry] = []

    private let defaults: UserDefaults

    private enum Keys {
        static let key = "pairingharness.identityPublicKey"
        static let uuid = "pairingharness.accountUUID"
        static let name = "pairingharness.displayName"
        static let contacts = "pairingharness.contacts"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Key and account id are kept or replaced together, never one alone.
        var stored: (key: Data, uuid: UUID)?
        if let key = defaults.data(forKey: Keys.key),
           let uuid = defaults.string(forKey: Keys.uuid).flatMap(UUID.init(uuidString:)) {
            stored = (key, uuid)
        }
        let key = stored?.key ?? Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        let uuid = stored?.uuid ?? UUID()
        let name = defaults.string(forKey: Keys.name) ?? "Harness \(Int.random(in: 1000...9999))"
        identityPublicKey = key
        accountUUID = uuid
        displayName = name
        contacts = defaults.data(forKey: Keys.contacts)
            .flatMap { try? JSONDecoder().decode([PairedContact].self, from: $0) } ?? []
        defaults.set(key, forKey: Keys.key)
        defaults.set(uuid.uuidString, forKey: Keys.uuid)
        defaults.set(name, forKey: Keys.name)
    }

    /// The text of this device's code, or nil while the name is unusable.
    var myCode: String? {
        try? PairingPayload(identityPublicKey: identityPublicKey,
                            accountUUID: accountUUID,
                            displayName: displayName).encoded()
    }

    enum ScanResult: Equatable {
        case added(name: String)
        case alreadyPaired(name: String)
        case refused(reason: String)
    }

    /// A scanned or pasted code.
    @discardableResult
    func handle(scanned: String) -> ScanResult {
        do {
            let outcome = try Pairing.evaluate(scanned: scanned,
                                               ownIdentityPublicKey: identityPublicKey,
                                               ownAccountUUID: accountUUID,
                                               contacts: contacts)
            switch outcome {
            case .newContact(let contact):
                contacts.append(contact)
                saveContacts()
                append("Added \(contact.displayName)", isError: false)
                return .added(name: contact.displayName)
            case .alreadyPaired(let contact):
                append("Already paired with \(contact.displayName); nothing changed", isError: false)
                return .alreadyPaired(name: contact.displayName)
            }
        } catch {
            let reason = Self.describe(error)
            append("Refused: \(reason)", isError: true)
            return .refused(reason: reason)
        }
    }

    func scannerFailed(_ failure: QRCodeScannerView.Failure) {
        switch failure {
        case .cameraUnavailable:
            append("No camera here (the Simulator has none). Paste a code instead.", isError: true)
        case .accessDenied:
            append("Camera access denied. Allow it in Settings, or paste a code.", isError: true)
        }
    }

    /// A different key and account id, as after a reinstall of the real app.
    func newIdentity() {
        identityPublicKey = Curve25519.KeyAgreement.PrivateKey().publicKey.rawRepresentation
        accountUUID = UUID()
        defaults.set(identityPublicKey, forKey: Keys.key)
        defaults.set(accountUUID.uuidString, forKey: Keys.uuid)
        append("New identity generated", isError: false)
    }

    func removeAllContacts() {
        contacts = []
        saveContacts()
        append("Contacts removed", isError: false)
    }

    static func fingerprint(_ key: Data) -> String {
        key.prefix(6).map { String(format: "%02x", $0) }.joined(separator: " ")
    }

    private func saveContacts() {
        defaults.set(try? JSONEncoder().encode(contacts), forKey: Keys.contacts)
    }

    func note(_ text: String) {
        append(text, isError: false)
    }

    private func append(_ text: String, isError: Bool) {
        log.insert(LogEntry(text: text, isError: isError), at: 0)
    }

    private static func describe(_ error: Error) -> String {
        guard let error = error as? PairingError else { return String(describing: error) }
        switch error {
        case .notAPairingCode: return "not a pairing code"
        case .unsupportedVersion(let version): return "code version \(version) is not supported"
        case .malformed: return "the code is damaged"
        case .invalidIdentityKey: return "the code carries an unusable key"
        case .invalidDisplayName: return "the name is empty"
        case .ownCode: return "this is your own code"
        case .conflictsWithExistingContact: return "conflicts with a stored contact"
        }
    }
}

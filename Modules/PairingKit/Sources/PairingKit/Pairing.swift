//
//  Pairing.swift
//  PairingKit
//
//  The decision taken on a scanned code. Pure: it reads nothing and stores
//  nothing, so the app and the harness cannot disagree about the rules.
//

import Foundation

/// What a successful scan leaves behind. Storing it is the caller's job.
public struct PairedContact: Equatable, Codable, Sendable, Identifiable {
    public let identityPublicKey: Data
    public let accountUUID: UUID
    /// The name the contact gave. A label, not an identifier — the user may
    /// replace it locally.
    public var displayName: String
    public let pairedAt: Date

    public var id: Data { identityPublicKey }

    public init(identityPublicKey: Data, accountUUID: UUID, displayName: String, pairedAt: Date) {
        self.identityPublicKey = identityPublicKey
        self.accountUUID = accountUUID
        self.displayName = displayName
        self.pairedAt = pairedAt
    }
}

public enum Pairing {

    public enum Outcome: Equatable, Sendable {
        /// Not seen before. Store it.
        case newContact(PairedContact)
        /// Same identity key and account id as a stored contact. Carries the
        /// STORED record; nothing changes, not even the name (the user may
        /// have renamed the contact).
        case alreadyPaired(PairedContact)
    }

    /// Checks a scanned code against this device's identity and its stored
    /// contacts.
    ///
    /// This only establishes what the other phone SHOWED. It cannot tell
    /// whether they scanned us back, nor that they hold the private key —
    /// both are settled by the first session
    /// (Architecture/pairing-workflow.md, "What a scan does not prove").
    ///
    /// - Throws: `PairingError`.
    public static func evaluate(scanned: String,
                                ownIdentityPublicKey: Data,
                                ownAccountUUID: UUID,
                                contacts: [PairedContact],
                                now: Date = Date()) throws -> Outcome {
        let payload = try PairingPayload(scanned: scanned)

        guard payload.identityPublicKey != ownIdentityPublicKey,
              payload.accountUUID != ownAccountUUID else {
            throw PairingError.ownCode
        }

        let sameKey = contacts.first { $0.identityPublicKey == payload.identityPublicKey }
        let sameAccount = contacts.first { $0.accountUUID == payload.accountUUID }
        switch (sameKey, sameAccount) {
        case (nil, nil):
            return .newContact(PairedContact(identityPublicKey: payload.identityPublicKey,
                                             accountUUID: payload.accountUUID,
                                             displayName: payload.displayName,
                                             pairedAt: now))
        case let (existing?, other?) where existing == other:
            return .alreadyPaired(existing)
        default:
            throw PairingError.conflictsWithExistingContact
        }
    }
}

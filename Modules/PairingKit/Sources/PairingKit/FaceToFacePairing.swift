//
//  FaceToFacePairing.swift
//  PairingKit
//
//  One attempt at pairing with the phones held face to face: each shows its
//  code and scans the other's at the same time
//  (Architecture/pairing-workflow.md, "Face to face").
//
//  Owns the rules of the attempt and nothing else: no camera, no screen, no
//  storage. The view shows `codeToShow`, feeds every scanned text to
//  `scanned(_:)`, and turns the returned event into feedback.
//

import Foundation

@MainActor
public final class FaceToFacePairing: ObservableObject {

    public enum Progress: Equatable, Sendable {
        case looking
        /// Their code is read and stored. They have not yet shown that they
        /// read ours.
        case readTheirs(PairedContact)
        /// Their code says they have ours too. Final for this attempt.
        case bothWays(PairedContact)
        /// The only code seen so far was refused. A good one replaces this.
        case refused(PairingError)
    }

    /// What just happened, for the caller to signal. Nobody can see their
    /// own screen in this position, so it should be felt or heard.
    public enum Event: Equatable, Sendable {
        case readTheirs(PairedContact)
        case completed(PairedContact)
        case refused(PairingError)
    }

    @Published public private(set) var progress: Progress = .looking
    /// Whose code this attempt has read. Goes into our own code as the
    /// "I have yours" marker.
    @Published private var peer: PairedContact?

    private let identityPublicKey: Data
    private let accountUUID: UUID
    private let displayName: String
    private let contacts: @MainActor () -> [PairedContact]
    private let store: @MainActor (PairedContact) -> Void
    private let now: @MainActor () -> Date
    /// The other code stays in view the whole time; each distinct text is
    /// acted on once.
    private var seen: Set<String> = []

    /// - Parameters:
    ///   - contacts: the stored contacts, read at each scan.
    ///   - store: called once, with a contact not seen before, as soon as
    ///     its code is read — NOT held back until the pairing is known to be
    ///     mutual. If the phones are pulled apart early, each side at least
    ///     keeps what it read, which is the same position a rear-camera scan
    ///     leaves it in.
    public init(identityPublicKey: Data,
                accountUUID: UUID,
                displayName: String,
                contacts: @escaping @MainActor () -> [PairedContact],
                store: @escaping @MainActor (PairedContact) -> Void,
                now: @escaping @MainActor () -> Date = { Date() }) {
        self.identityPublicKey = identityPublicKey
        self.accountUUID = accountUUID
        self.displayName = displayName
        self.contacts = contacts
        self.store = store
        self.now = now
    }

    /// The text for this device's QR code, or nil if the identity or the
    /// name cannot be put in a code. Changes once, when their code is read.
    public var codeToShow: String? {
        try? PairingPayload(identityPublicKey: identityPublicKey,
                            accountUUID: accountUUID,
                            displayName: displayName,
                            acknowledging: peer?.identityPublicKey).encoded()
    }

    /// Feed every text the scanner reports.
    ///
    /// - Returns: the event to signal, or nil when nothing changed.
    @discardableResult
    public func scanned(_ text: String) -> Event? {
        if case .bothWays = progress { return nil }
        guard seen.insert(text).inserted else { return nil }

        let evaluation: Pairing.Evaluation
        do {
            evaluation = try Pairing.evaluate(scanned: text,
                                              ownIdentityPublicKey: identityPublicKey,
                                              ownAccountUUID: accountUUID,
                                              contacts: contacts(),
                                              now: now())
        } catch {
            // Once a peer is read, a stray code passing the camera must not
            // undo that.
            guard peer == nil, let error = error as? PairingError else { return nil }
            progress = .refused(error)
            return .refused(error)
        }

        let contact = evaluation.contact
        // One attempt, one peer: a third phone's code is ignored, not stored.
        if let peer, peer.identityPublicKey != contact.identityPublicKey { return nil }

        if case .newContact = evaluation.outcome { store(contact) }
        let isFirstRead = peer == nil
        peer = contact

        if evaluation.peerHasScannedUs {
            progress = .bothWays(contact)
            return .completed(contact)
        }
        guard isFirstRead else { return nil }
        progress = .readTheirs(contact)
        return .readTheirs(contact)
    }

    /// Forget this attempt (not the stored contacts) and start another.
    public func restart() {
        seen = []
        peer = nil
        progress = .looking
    }
}

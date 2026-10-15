//
//  PairingViewModel.swift
//  SecureChat
//
//  Drives the "Add contact" screen: two phones held face to face, each
//  showing its code and reading the other's (Architecture/pairing-workflow.md).
//  The rules of the attempt are PairingKit's `FaceToFacePairing`, and the
//  screen is PairingKit's `FaceToFacePairingView`; this adds what is the
//  app's own: who we are, our name, where contacts are stored, and which
//  scans count.
//

import Foundation
import PairingKit

@MainActor @Observable
final class PairingViewModel {

    enum Phase {
        /// No display name yet; pairing cannot build a code without one.
        case needsName
        case pairing(FaceToFacePairing)
        /// Pairing cannot run. The message is for the user.
        case unavailable(String)
    }

    private(set) var phase: Phase = .needsName
    /// Bound to the name field while `phase` is `.needsName`.
    var draftName = ""

    @ObservationIgnored private let identity: () throws -> LocalIdentity
    @ObservationIgnored private let contacts: ContactRepository
    @ObservationIgnored private let profile: ProfileStore

    init(identity: @escaping () throws -> LocalIdentity,
         contacts: ContactRepository,
         profile: ProfileStore = ProfileStore()) {
        self.identity = identity
        self.contacts = contacts
        self.profile = profile
        start()
    }

    var canConfirmName: Bool {
        !PairingPayload.normalizedName(draftName).isEmpty
    }

    func confirmName() {
        let name = PairingPayload.normalizedName(draftName)
        guard !name.isEmpty else { return }
        profile.displayName = name
        start()
    }

    /// A code read by the camera. Returns what the screen should signal,
    /// or nil for nothing.
    func scanned(_ text: String) -> FaceToFacePairing.Event? {
        guard case .pairing(let pairing) = phase, let event = pairing.scanned(text) else { return nil }
        // Storing may have failed inside `scanned`; then the phase has moved
        // on and there is nothing to celebrate.
        guard case .pairing = phase else { return nil }
        if case .refused(let error) = event {
            SCLogger.logger.info(message: "Pairing code refused: \(error)", category: .Pairing)
        }
        return event
    }

#if DEBUG
    /// For the pairing debug sheet: the account id this phone pairs with.
    var debugAccount: String {
        (try? identity().accountUUID.uuidString) ?? "none (not registered)"
    }
#endif

    func scannerFailed(_ failure: QRCodeScannerView.Failure) {
        SCLogger.logger.info(message: "Pairing scanner unavailable: \(failure)", category: .Pairing)
    }

    // MARK: Private

    private func start() {
        guard let name = profile.displayName, !PairingPayload.normalizedName(name).isEmpty else {
            phase = .needsName
            return
        }
        do {
            let me = try identity()
            let pairing = FaceToFacePairing(
                identityPublicKey: me.identityPublicKey,
                accountUUID: me.accountUUID,
                displayName: name,
                contacts: { [contacts] in contacts.contacts },
                store: { [weak self] in self?.store($0) })
            guard pairing.codeToShow != nil else {
                SCLogger.logger.error(message: "Pairing: no code could be built from this identity", category: .Pairing)
                phase = .unavailable("Pairing isn't available right now.")
                return
            }
            phase = .pairing(pairing)
        } catch LocalIdentityError.notRegistered {
            phase = .unavailable("Register this device before adding a contact.")
        } catch {
            SCLogger.logger.error(message: "Pairing: identity could not be read", error: error, category: .Pairing)
            phase = .unavailable("Couldn't access secure storage. Unlock your device and try again.")
        }
    }

    private func store(_ contact: PairedContact) {
        do {
            try contacts.add(contact)
        } catch {
            SCLogger.logger.error(message: "Pairing: contact could not be saved", error: error, category: .Pairing)
            phase = .unavailable("The contact couldn't be saved. Please try again.")
        }
    }
}

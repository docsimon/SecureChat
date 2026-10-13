//
//  PairingViewModel.swift
//  SecureChat
//
//  Drives the "Add contact" screen: two phones held face to face, each
//  showing its code and reading the other's (Architecture/pairing-workflow.md).
//  The rules of the attempt are PairingKit's `FaceToFacePairing`; this adds
//  what is the app's own: who we are, where contacts are stored, and how
//  the result is signalled.
//

import Foundation
import AudioToolbox
import UIKit
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
    var camera: QRCodeScannerView.Camera = .front
    /// Why the camera is not reading, when it is not. The code is still
    /// shown: the other phone can read this one regardless.
    private(set) var scannerProblem: QRCodeScannerView.Failure?

    @ObservationIgnored private let identity: () throws -> LocalIdentity
    @ObservationIgnored private let contacts: ContactRepository
    @ObservationIgnored private let profile: ProfileStore
    @ObservationIgnored private let signal: (FaceToFacePairing.Event) -> Void

    init(identity: @escaping () throws -> LocalIdentity,
         contacts: ContactRepository,
         profile: ProfileStore = ProfileStore(),
         signal: @escaping (FaceToFacePairing.Event) -> Void = PairingViewModel.liveSignal) {
        self.identity = identity
        self.contacts = contacts
        self.profile = profile
        self.signal = signal
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

    func scanned(_ text: String) {
        guard case .pairing(let pairing) = phase, let event = pairing.scanned(text) else { return }
        // Storing may have failed inside `scanned`; then the phase has moved
        // on and there is nothing to celebrate.
        guard case .pairing = phase else { return }
        if case .refused(let error) = event {
            SCLogger.logger.info(message: "Pairing code refused: \(error)", category: .Pairing)
        }
        signal(event)
    }

    func scannerFailed(_ failure: QRCodeScannerView.Failure) {
        scannerProblem = failure
    }

    func cameraChanged() {
        scannerProblem = nil
        if case .pairing(let pairing) = phase { pairing.restart() }
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

    /// Nobody sees their own screen while the phones face each other, so the
    /// result has to be felt and heard. The full vibration is what was
    /// confirmed on phones; `UIFeedbackGenerator` alone could not be felt.
    static let liveSignal: (FaceToFacePairing.Event) -> Void = { event in
        switch event {
        case .readTheirs:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .completed:
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
            AudioServicesPlaySystemSound(1016)
        case .refused:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

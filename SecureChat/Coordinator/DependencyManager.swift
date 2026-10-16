//
// DependencyManager.swift
// SecureChat
//
// Created by Simone Barbara on 08/10/2025.
// All Rights Reserved.

import Foundation
import AppAttestKit
import PairingKit
import RegistrationKit
import SessionKit

@MainActor
final class DependencyManager {

    /// One per process: it owns the App Attest state machine, and two of
    /// them would write the same Keychain state.
    let attestationCoordinator: AttestationCoordinator
    let registrationViewModel: RegistrationViewModel
    let contactRepo: ContactRepository
    let messageStore: MessageStore
    let relayConnection: RelayConnection
    private var identityProvider = LocalIdentityProvider()

    init() {
        let db: DatabaseStrategy
        do {
            db = try SQLiteDB(path: DatabaseLocation.prepare())
            SCLogger.logger.info(message: LogMessage.SQLiteDBCreated, category: .Database)
        } catch {
            SCLogger.logger.error(message: LogMessage.SQLiteDBNotCreated, error: error, category: .Database)
            fatalError()
        }

        // Registration
        var transport: AttestationTransport = RealAttestationTransport(baseURL: AuthServerEnvironment.baseURL)
#if DEBUG
        transport = EnvironmentLoggingTransport(base: transport)
#endif
        attestationCoordinator = AttestationCoordinator(transport: transport, observer: RegistrationLogObserver())
        registrationViewModel = RegistrationViewModel(coordinator: attestationCoordinator)
        var credentials = RelayCredentials(
            sessionClient: SessionClient(baseURL: AuthServerEnvironment.baseURL, signer: attestationCoordinator))
#if DEBUG
        // Debug builds skip registration, so running the app never spends an
        // App Attest key. The real flow (development App Attest + the local
        // Auth Server) runs only from the "SecureChat Real Registration"
        // scheme, which passes the launch argument `-RealRegistration YES`.
        registrationViewModel.assumesRegistered = !UserDefaults.standard.bool(forKey: "RealRegistration")
        // A run that skipped registration has no identity to pair with, and
        // the Auth Server has no token for it: the relay's development flag
        // lets it in by account id.
        identityProvider.usesDebugIdentity = registrationViewModel.assumesRegistered
        credentials.usesDevelopmentAccount = registrationViewModel.assumesRegistered
#endif
        // Pairing
        contactRepo = ContactRepository(db: db)
        // Sessions
        messageStore = MessageStore(db: db, keys: .live,
                                    keepKeysFor: Set(contactRepo.contacts.map(\.accountUUID)))
        let identityProvider = identityProvider
        relayConnection = RelayConnection(
            identity: identityProvider.loadForSessions,
            credential: credentials.credential(for:),
            makeTransport: { RelayClient(url: RelayEnvironment.url, credential: $0) },
            contacts: contactRepo,
            messages: messageStore)
    }

    func makePairingViewModel() -> PairingViewModel {
        PairingViewModel(identity: identityProvider.load, contacts: contactRepo)
    }

    func makeConversationViewModel(with contact: PairedContact) -> ConversationViewModel {
        ConversationViewModel(contact: contact, connection: relayConnection, store: messageStore)
    }
}

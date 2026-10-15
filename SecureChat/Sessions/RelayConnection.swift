//
//  RelayConnection.swift
//  SecureChat
//
//  The app's one relay connection and the sessions on it
//  (session-workflow.md, "SecureChat"). Connected while the app is in the
//  foreground, closed in the background, reconnected after a drop. Opening
//  a chat opens a session with that contact; every message, sent or
//  received, goes to the MessageStore.
//
//  Sessions live and die with the connection (§1): a new connection starts
//  with none, and what was waiting for a session is marked not delivered.
//

import Foundation
import AppAttestKit
import SessionKit

@MainActor @Observable
final class RelayConnection {

    enum PeerStatus: Equatable {
        case starting
        case open
        /// Not connected to the relay.
        case offline
        /// Connected but silent: what a contact who removed us looks like.
        case unanswered
        /// A message failed to decrypt. The next one starts a new session.
        case ended
    }

    private(set) var state: RelayClient.State = .disconnected
    /// Only peers something has happened with on this connection.
    private(set) var peerStatus: [UUID: PeerStatus] = [:]

    @ObservationIgnored private let identity: () throws -> SessionIdentity
    @ObservationIgnored private let credential: (SessionIdentity) async throws -> RelayClient.Credential
    @ObservationIgnored private let makeTransport: (RelayClient.Credential) -> RelayTransport
    @ObservationIgnored private let contacts: ContactRepository
    @ObservationIgnored private let messages: MessageStore
    @ObservationIgnored private let handshakeTimeout: UInt64
    @ObservationIgnored private let retryDelays: [UInt64]
    @ObservationIgnored private let stableAfter: TimeInterval

    @ObservationIgnored private var service: SessionService?
    /// Fetching a credential, or waiting to retry. At most one.
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var openChat: UUID?
    @ObservationIgnored private var failures = 0
    @ObservationIgnored private var connectedAt: Date?

    /// - Parameters:
    ///   - makeTransport: a `RelayClient` in the app, an in-process relay in
    ///     the integration tests.
    ///   - retryDelays: nanoseconds to wait after each consecutive failure;
    ///     the last one repeats.
    ///   - stableAfter: seconds a connection must last to count as a
    ///     success. The relay opens the WebSocket before checking the
    ///     credential and then closes it, so "connected" alone proves
    ///     nothing; without this a refused credential would retry every
    ///     second, each time asking the Auth Server for a token.
    init(identity: @escaping () throws -> SessionIdentity,
         credential: @escaping (SessionIdentity) async throws -> RelayClient.Credential,
         makeTransport: @escaping (RelayClient.Credential) -> RelayTransport,
         contacts: ContactRepository,
         messages: MessageStore,
         handshakeTimeout: UInt64 = SessionService.handshakeTimeout,
         retryDelays: [UInt64] = [1, 2, 5, 10].map { $0 * 1_000_000_000 },
         stableAfter: TimeInterval = 10) {
        self.identity = identity
        self.credential = credential
        self.makeTransport = makeTransport
        self.contacts = contacts
        self.messages = messages
        self.handshakeTimeout = handshakeTimeout
        self.retryDelays = retryDelays
        self.stableAfter = stableAfter
    }

    /// True in the foreground, false in the background.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active {
            failures = 0
            connect()
        } else {
            pending?.cancel()
            pending = nil
            if let service {
                service.disconnect()   // reports .disconnected, which cleans up
            } else {
                state = .disconnected
            }
        }
    }

    /// A chat with `peer` is on screen: open a session, now or once connected.
    func chatOpened(with peer: UUID) {
        openChat = peer
        open(peer)
    }

    func chatClosed(with peer: UUID) {
        if openChat == peer { openChat = nil }
    }

    /// Stored whatever happens; its status says whether it left.
    func send(_ text: String, to peer: UUID) {
        let isOpen = service?.established.contains(peer) ?? false
        var message = StoredMessage(peer: peer, text: text, status: isOpen ? .sent : .waiting)
        do {
            guard let service else { throw RelayClientError.notConnected }
            try service.send(text, to: peer)
            if !isOpen { peerStatus[peer] = .starting }
        } catch {
            SCLogger.logger.error(message: "Message not sent", error: error, category: .Session)
            message.status = .notDelivered
        }
        messages.add(message)
    }

    // MARK: Connection

    private func connect() {
        guard isActive, service == nil, pending == nil else { return }
        state = .connecting
        pending = Task { [weak self] in
            guard let self else { return }
            do {
                let identity = try self.identity()
                let credential = try await self.credential(identity)
                guard !Task.isCancelled else { return }
                self.pending = nil
                self.start(identity: identity, credential: credential)
            } catch {
                guard !Task.isCancelled else { return }
                self.pending = nil
                // The name only: an AttestationError can carry a server
                // response body (as in RegistrationViewModel).
                let name = (error as? AttestationError)?.diagnosticName ?? String(describing: type(of: error))
                SCLogger.logger.error(message: "No relay credential: \(name)", category: .Session)
                self.state = .disconnected
                self.scheduleRetry()
            }
        }
    }

    private func start(identity: SessionIdentity, credential: RelayClient.Credential) {
        let service = SessionService(
            transport: makeTransport(credential),
            localIdentity: identity.privateKey,
            localAccount: identity.accountUUID,
            handshakeTimeout: handshakeTimeout,
            contactKey: { [contacts] account in
                contacts.contacts.first { $0.accountUUID == account }?.identityPublicKey
            })
        service.onEvent = { [weak self] event in self?.handle(event) }
        service.onRelayStateChange = { [weak self] state in self?.relayStateChanged(state) }
        self.service = service
        service.connect()
    }

    private func relayStateChanged(_ newState: RelayClient.State) {
        state = newState
        switch newState {
        case .connecting:
            break
        case .connected:
            connectedAt = Date()
            SCLogger.logger.info(message: "Relay connected", category: .Session)
            if let openChat { open(openChat) }
        case .disconnected:
            if let connectedAt, Date().timeIntervalSince(connectedAt) >= stableAfter { failures = 0 }
            connectedAt = nil
            // The relay client has closed itself; nothing left to release.
            service = nil
            peerStatus.removeAll()
            messages.resolveAllWaiting(as: .notDelivered)
            SCLogger.logger.info(message: "Relay disconnected", category: .Session)
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard isActive, service == nil, pending == nil else { return }
        let delay = retryDelays[min(failures, retryDelays.count - 1)]
        failures += 1
        pending = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self, !Task.isCancelled else { return }
            self.pending = nil
            self.connect()
        }
    }

    // MARK: Sessions

    private func open(_ peer: UUID) {
        guard let service, service.relayState == .connected, !service.established.contains(peer) else { return }
        do {
            try service.open(peer)
            peerStatus[peer] = .starting
        } catch {
            SCLogger.logger.error(message: "Session not started", error: error, category: .Session)
        }
    }

    private func handle(_ event: SessionService.Event) {
        switch event {
        case .established(let peer):
            peerStatus[peer] = .open
            messages.resolveWaiting(with: peer, as: .sent)
        case .received(let peer, let content):
            switch content {
            case .text(let text):
                messages.add(StoredMessage(peer: peer, text: text, status: .received))
            }
        case .peerUnavailable(let peer, _):
            peerStatus[peer] = .offline
            messages.resolveWaiting(with: peer, as: .notDelivered)
        case .unanswered(let peer, _):
            peerStatus[peer] = .unanswered
            messages.resolveWaiting(with: peer, as: .notDelivered)
        case .ended(let peer):
            peerStatus[peer] = .ended
            messages.resolveWaiting(with: peer, as: .notDelivered)
        case .refused(_, let refusal):
            // Never the id: a stranger's address is nobody's business.
            SCLogger.logger.info(message: "Session refused: \(refusal)", category: .Session)
        }
    }
}

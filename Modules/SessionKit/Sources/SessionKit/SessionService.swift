//
//  SessionService.swift
//  SessionKit
//
//  The engine and the relay connection together, for the harness and the
//  app. Addresses peers by account UUID; routing ids stay inside SessionKit.
//

import Foundation
import CryptoKit

@MainActor
public final class SessionService: ObservableObject {

    public enum Event: Equatable {
        case established(UUID)
        case received(UUID, SessionContent)
        /// Not connected to the relay. What was waiting for them is dropped.
        case peerUnavailable(UUID, dropped: [SessionContent])
        case refused(UUID, SessionEngine.Refusal)
        case ended(UUID)
        /// They did not answer the handshake within `handshakeTimeout`. Also
        /// what a contact who removed us looks like: deliberately silent.
        case unanswered(UUID, dropped: [SessionContent])
    }

    /// How long a handshake may go unanswered. The relay answers at once
    /// when the peer is offline, so this only runs out when the peer is
    /// connected but stays silent.
    public static let handshakeTimeout: UInt64 = 10_000_000_000

    @Published public private(set) var relayState: RelayClient.State = .disconnected
    /// Peers with an open session.
    @Published public private(set) var established: Set<UUID> = []
    public var onEvent: ((Event) -> Void)?

    private let engine: SessionEngine
    private let relay: RelayClient
    /// Frames leave in the order they were encrypted: the receiver's Noise
    /// nonce counts them, so a reordered pair would end the session.
    private var lastSend: Task<Void, Never>?
    private var handshakeTimeouts: [UUID: Task<Void, Never>] = [:]

    /// - Parameters:
    ///   - localIdentity: this device's identity key.
    ///   - contactKey: the stored identity public key (32 bytes) of a
    ///     contact, or nil for anyone else.
    /// The relay client keeps itself alive while connected: call
    /// `disconnect()` before letting go of this service.
    public init(relayURL: URL,
                credential: RelayClient.Credential,
                localIdentity: Curve25519.KeyAgreement.PrivateKey,
                localAccount: UUID,
                contactKey: @escaping (UUID) -> Data?) {
        engine = SessionEngine(localStatic: localIdentity,
                               localRoutingID: RoutingID.of(accountUUID: localAccount),
                               contactKey: { routingID in
                                   RoutingID.accountUUID(routingID).flatMap(contactKey)
                                       .flatMap { try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: $0) }
                               })
        relay = RelayClient(url: relayURL, credential: credential)
        relay.onStateChange = { [weak self] state in self?.relayStateChanged(state) }
        relay.onFrame = { [weak self] frame in self?.handle(self?.engine.receive(frame)) }
    }

    public func connect() {
        relay.connect()
    }

    public func disconnect() {
        relay.disconnect()
    }

    /// Opening a chat. No-op if a session exists or is starting.
    public func open(_ peer: UUID) throws {
        try requireConnection()
        handle(try engine.open(RoutingID.of(accountUUID: peer)))
        watchHandshake(with: peer)
    }

    /// Opens the session first if needed; the text goes out once it is open.
    public func send(_ text: String, to peer: UUID) throws {
        try requireConnection()
        handle(try engine.send(.text(text), to: RoutingID.of(accountUUID: peer)))
        watchHandshake(with: peer)
    }

    // MARK: Private

    private func watchHandshake(with peer: UUID) {
        let routingID = RoutingID.of(accountUUID: peer)
        guard engine.isHandshaking(with: routingID), handshakeTimeouts[peer] == nil else { return }
        handshakeTimeouts[peer] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.handshakeTimeout)
            guard let self, !Task.isCancelled else { return }
            self.handshakeTimeouts[peer] = nil
            self.handle(self.engine.abandonHandshake(with: routingID))
        }
    }

    private func requireConnection() throws {
        guard relayState == .connected else { throw RelayClientError.notConnected }
    }

    private func relayStateChanged(_ state: RelayClient.State) {
        relayState = state
        if state == .disconnected {
            // Sessions live and die with the connection (§1).
            engine.reset()
            established.removeAll()
            handshakeTimeouts.values.forEach { $0.cancel() }
            handshakeTimeouts.removeAll()
        }
    }

    private func handle(_ output: SessionEngine.Output?) {
        guard let output else { return }
        if !output.frames.isEmpty {
            let previous = lastSend
            let frames = output.frames
            lastSend = Task { [relay] in
                await previous?.value
                // A failed send means the connection dropped; the relay
                // client reports that through its state.
                try? await relay.send(frames)
            }
        }
        for event in output.events {
            guard let mapped = map(event) else { continue }
            switch mapped {
            case .established(let peer):
                established.insert(peer)
                handshakeTimeouts.removeValue(forKey: peer)?.cancel()
            case .peerUnavailable(let peer, _), .unanswered(let peer, _):
                established.remove(peer)
                handshakeTimeouts.removeValue(forKey: peer)?.cancel()
            case .ended(let peer):
                established.remove(peer)
            case .received, .refused:
                break
            }
            onEvent?(mapped)
        }
    }

    private func map(_ event: SessionEngine.Event) -> Event? {
        switch event {
        case .established(let peer):
            return RoutingID.accountUUID(peer).map { .established($0) }
        case .received(let peer, let content):
            return RoutingID.accountUUID(peer).map { .received($0, content) }
        case .peerUnavailable(let peer, let dropped):
            return RoutingID.accountUUID(peer).map { .peerUnavailable($0, dropped: dropped) }
        case .refused(let peer, let refusal):
            return RoutingID.accountUUID(peer).map { .refused($0, refusal) }
        case .ended(let peer, _):
            return RoutingID.accountUUID(peer).map { .ended($0) }
        case .unanswered(let peer, let dropped):
            return RoutingID.accountUUID(peer).map { .unanswered($0, dropped: dropped) }
        }
    }
}

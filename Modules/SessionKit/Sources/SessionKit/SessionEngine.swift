//
//  SessionEngine.swift
//  SessionKit
//
//  One device's sessions, one per peer (session-workflow.md, "Protocol").
//  Pure logic: it is given frames and user actions and answers with the
//  frames to send and what happened. It never touches the network, so the
//  whole protocol is testable with two engines passing frames by hand.
//
//  Not thread safe: confine it to one actor (the app uses the main actor).
//

import Foundation
import CryptoKit

public final class SessionEngine {

    public enum Event: Equatable {
        /// Messages can flow both ways.
        case established(peer: Data)
        case received(peer: Data, SessionContent)
        /// The relay says the peer is not connected. Anything queued for
        /// them was dropped: nothing is stored for later (§1).
        case peerUnavailable(peer: Data, dropped: [SessionContent])
        /// A first message nobody should act on. No answer was sent.
        case refused(peer: Data, Refusal)
        /// The session broke. The next `send` starts a new handshake.
        case ended(peer: Data, EndReason)
        /// Our handshake got no answer in time (`abandonHandshake`). Expected
        /// when they do not have us as a contact: they stay silent on
        /// purpose. What was queued for them was dropped.
        case unanswered(peer: Data, dropped: [SessionContent])
    }

    public enum Refusal: Equatable {
        /// Not a stored contact. Expected: anyone can address a frame to us.
        case notAContact
        /// A contact's id, but the handshake did not authenticate.
        case handshakeFailed
    }

    public enum EndReason: Equatable {
        case decryptFailed
    }

    public struct Output: Equatable {
        /// Encoded relay frames, in order.
        public var frames: [Data] = []
        public var events: [Event] = []
    }

    /// v2: the Double Ratchet. A v1 peer fails the handshake instead of
    /// misreading messages.
    public static let prologue = Data("SecureChat session v2".utf8)

    /// The open session: Noise carries the ratchet's messages, so the relay
    /// never sees the ratchet's headers.
    private struct Established {
        var transport: NoiseTransport
        var ratchet: DoubleRatchet
    }

    private enum State {
        /// Our first ratchet key went out in handshake 1's payload.
        case initiating(NoiseKKInitiator, ratchetKey: Curve25519.KeyAgreement.PrivateKey)
        case established(Established)
    }

    private let localStatic: Curve25519.KeyAgreement.PrivateKey
    private let localRoutingID: Data
    private let contactKey: (Data) -> Curve25519.KeyAgreement.PublicKey?
    private var sessions: [Data: State] = [:]
    /// Written before the session was open; sent as soon as it is.
    private var queued: [Data: [SessionContent]] = [:]

    /// - Parameters:
    ///   - localStatic: this device's identity key.
    ///   - localRoutingID: this device's routing id, for the tie-break.
    ///   - contactKey: the stored identity key for a routing id, or nil when
    ///     it is not a contact. Asked on every first message, so a contact
    ///     added while running is known at once.
    public init(localStatic: Curve25519.KeyAgreement.PrivateKey,
                localRoutingID: Data,
                contactKey: @escaping (Data) -> Curve25519.KeyAgreement.PublicKey?) {
        self.localStatic = localStatic
        self.localRoutingID = localRoutingID
        self.contactKey = contactKey
    }

    public func isEstablished(with peer: Data) -> Bool {
        if case .established = sessions[peer] { return true }
        return false
    }

    public func isHandshaking(with peer: Data) -> Bool {
        if case .initiating = sessions[peer] { return true }
        return false
    }

    /// Gives up on our handshake with `peer` if it is still unanswered. The
    /// caller decides when (SessionService uses a timeout). Without this, a
    /// peer who never answers would leave the session stuck "starting" and
    /// every later `open` a no-op.
    public func abandonHandshake(with peer: Data) -> Output {
        guard isHandshaking(with: peer) else { return Output() }
        sessions[peer] = nil
        return Output(events: [.unanswered(peer: peer, dropped: queued.removeValue(forKey: peer) ?? [])])
    }

    /// Opening a chat: starts the handshake unless a session exists or is
    /// already starting.
    public func open(_ peer: Data) throws -> Output {
        var output = Output()
        guard sessions[peer] == nil else { return output }
        guard let remote = contactKey(peer) else { throw SessionError.notAContact }
        var initiator = NoiseKKInitiator(prologue: Self.prologue, localStatic: localStatic, remoteStatic: remote)
        let ratchetKey = Curve25519.KeyAgreement.PrivateKey()
        let message = try initiator.writeMessage1(payload: ratchetKey.publicKey.rawRepresentation)
        sessions[peer] = .initiating(initiator, ratchetKey: ratchetKey)
        output.frames.append(try frame(to: peer, .handshake1, message))
        return output
    }

    /// Sends now if the session is open, otherwise queues and opens it.
    public func send(_ content: SessionContent, to peer: Data) throws -> Output {
        // Refuse what cannot be sent before queueing it.
        _ = try content.padded()
        guard contactKey(peer) != nil else { throw SessionError.notAContact }
        switch sessions[peer] {
        case .established(var session):
            let output = Output(frames: [try transportFrame(content, to: peer, using: &session)])
            sessions[peer] = .established(session)
            return output
        case .initiating:
            queued[peer, default: []].append(content)
            return Output()
        case nil:
            queued[peer, default: []].append(content)
            return try open(peer)
        }
    }

    /// Forgets every session (the relay connection closed).
    public func reset() {
        sessions.removeAll()
        queued.removeAll()
    }

    public func receive(_ data: Data) -> Output {
        guard let frame = try? RelayFrame(decoding: data) else { return Output() }
        let peer = frame.peer
        switch frame.kind {
        case .peerUnavailable:
            sessions[peer] = nil
            return Output(events: [.peerUnavailable(peer: peer, dropped: queued.removeValue(forKey: peer) ?? [])])
        case .deliver:
            guard let packet = try? SessionPacket(decoding: frame.body) else { return Output() }
            switch packet.type {
            case .handshake1: return receiveHandshake1(packet.message, from: peer)
            case .handshake2: return receiveHandshake2(packet.message, from: peer)
            case .transport: return receiveTransport(packet.message, from: peer)
            }
        }
    }

    // MARK: Receiving

    private func receiveHandshake1(_ message: Data, from peer: Data) -> Output {
        guard let remote = contactKey(peer) else {
            return Output(events: [.refused(peer: peer, .notAContact)])
        }
        // Both opened the chat at once: the lower id stays initiator, and
        // the other side will answer our handshake instead.
        if case .initiating = sessions[peer], localRoutingID.lexicographicallyPrecedes(peer) {
            return Output()
        }
        var responder = NoiseKKResponder(prologue: Self.prologue, localStatic: localStatic, remoteStatic: remote)
        do {
            let remoteRatchetKey = try ratchetKey(in: try responder.readMessage1(message))
            let ratchetKey = Curve25519.KeyAgreement.PrivateKey()
            let (reply, transport) = try responder.writeMessage2(payload: ratchetKey.publicKey.rawRepresentation)
            let ratchet = try DoubleRatchet.responder(secret: transport.ratchetSecret,
                                                      sessionBinding: transport.handshakeHash,
                                                      ownKey: ratchetKey, remoteKey: remoteRatchetKey)
            sessions[peer] = .established(Established(transport: transport, ratchet: ratchet))
            var output = Output(frames: [try frame(to: peer, .handshake2, reply)],
                                events: [.established(peer: peer)])
            output.frames += flushQueue(for: peer)
            return output
        } catch {
            // Leaves any running session alone: a forged first message must
            // not be able to end it.
            return Output(events: [.refused(peer: peer, .handshakeFailed)])
        }
    }

    private func receiveHandshake2(_ message: Data, from peer: Data) -> Output {
        guard case .initiating(var initiator, let ratchetKey) = sessions[peer] else { return Output() }
        do {
            let (payload, transport) = try initiator.readMessage2(message)
            let ratchet = try DoubleRatchet.initiator(secret: transport.ratchetSecret,
                                                      sessionBinding: transport.handshakeHash,
                                                      ownKey: ratchetKey, remoteKey: try self.ratchetKey(in: payload))
            sessions[peer] = .established(Established(transport: transport, ratchet: ratchet))
            var output = Output(events: [.established(peer: peer)])
            output.frames += flushQueue(for: peer)
            return output
        } catch {
            sessions[peer] = nil
            return Output(events: [.refused(peer: peer, .handshakeFailed)])
        }
    }

    private func receiveTransport(_ message: Data, from peer: Data) -> Output {
        guard case .established(var session) = sessions[peer] else { return Output() }
        do {
            let plaintext = try session.ratchet.decrypt(try session.transport.receive.decrypt(message))
            sessions[peer] = .established(session)
            return Output(events: [.received(peer: peer, try SessionContent(unpadding: plaintext))])
        } catch {
            sessions[peer] = nil
            return Output(events: [.ended(peer: peer, .decryptFailed)])
        }
    }

    // MARK: Helpers

    private func flushQueue(for peer: Data) -> [Data] {
        guard case .established(var session) = sessions[peer],
              let pending = queued.removeValue(forKey: peer) else { return [] }
        // Content was checked when it was queued, so this cannot fail.
        let frames = pending.compactMap { try? transportFrame($0, to: peer, using: &session) }
        sessions[peer] = .established(session)
        return frames
    }

    /// Ratchet first, then Noise around it.
    private func transportFrame(_ content: SessionContent, to peer: Data,
                                using session: inout Established) throws -> Data {
        let inner = try session.ratchet.encrypt(try content.padded())
        return try frame(to: peer, .transport, try session.transport.send.encrypt(inner))
    }

    /// The peer's first ratchet key, from a handshake payload.
    private func ratchetKey(in payload: Data) throws -> Curve25519.KeyAgreement.PublicKey {
        guard payload.count == 32 else { throw RatchetError.malformedMessage }
        do {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: payload)
        } catch {
            throw RatchetError.invalidPublicKey
        }
    }

    private func frame(to peer: Data, _ type: SessionPacket.PacketType, _ message: Data) throws -> Data {
        try RelayFrame(kind: .deliver, peer: peer,
                       body: try SessionPacket(type: type, message: message).encoded()).encoded()
    }
}

public enum SessionError: Error, Equatable {
    case notAContact
}

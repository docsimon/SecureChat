//
//  Frames.swift
//  SessionKit
//
//  The bytes on the wire (session-workflow.md, "Wire format"). Every frame,
//  in both directions, is exactly `RelayFrame.size` bytes, and every
//  transport message is padded to one length BEFORE encryption, so neither
//  the relay nor anyone watching learns how long a message is.
//

import Foundation

/// The 16 opaque bytes the relay routes by. Produced in one place so a
/// derived rendezvous id can replace the account UUID later without a
/// format change (architecture-decisions.md §10).
public enum RoutingID {
    public static let size = 16

    public static func of(accountUUID: UUID) -> Data {
        withUnsafeBytes(of: accountUUID.uuid) { Data($0) }
    }

    public static func accountUUID(_ routingID: Data) -> UUID? {
        guard routingID.count == size else { return nil }
        let b = [UInt8](routingID)
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

public enum FrameError: Error, Equatable {
    case wrongSize(Int)
    case unsupportedVersion(UInt8)
    case unknownKind(UInt8)
    case unknownType(UInt8)
    case malformed
    /// More content than one frame holds.
    case tooLong
}

/// What travels between a client and the relay.
public struct RelayFrame: Equatable {
    public static let size = 8_320
    public static let version: UInt8 = 1
    static let headerSize = 2 + RoutingID.size
    public static let bodySize = size - headerSize

    public enum Kind: UInt8 {
        /// A session packet. Client→relay: for `peer`. Relay→client: from `peer`.
        case deliver = 1
        /// Relay→client: `peer` is not connected. The body is empty.
        case peerUnavailable = 2
    }

    public let kind: Kind
    public let peer: Data
    /// At most `bodySize` bytes; padded with zeros on the wire.
    public let body: Data

    public init(kind: Kind, peer: Data, body: Data = Data()) {
        self.kind = kind
        self.peer = peer
        self.body = body
    }

    public func encoded() throws -> Data {
        guard peer.count == RoutingID.size else { throw FrameError.malformed }
        guard body.count <= Self.bodySize else { throw FrameError.tooLong }
        var data = Data([Self.version, kind.rawValue]) + peer + body
        data.append(Data(count: Self.size - data.count))
        return data
    }

    public init(decoding data: Data) throws {
        guard data.count == Self.size else { throw FrameError.wrongSize(data.count) }
        let bytes = [UInt8](data)
        guard bytes[0] == Self.version else { throw FrameError.unsupportedVersion(bytes[0]) }
        guard let kind = Kind(rawValue: bytes[1]) else { throw FrameError.unknownKind(bytes[1]) }
        self.kind = kind
        peer = Data(bytes[2..<Self.headerSize])
        body = Data(bytes[Self.headerSize...])
    }
}

/// The body of a `deliver` frame: one Noise message.
struct SessionPacket: Equatable {
    enum PacketType: UInt8 {
        case handshake1 = 1
        case handshake2 = 2
        case transport = 3
    }

    static let headerSize = 3
    static let maxMessageSize = RelayFrame.bodySize - headerSize

    let type: PacketType
    let message: Data

    func encoded() throws -> Data {
        guard message.count <= Self.maxMessageSize else { throw FrameError.tooLong }
        return Data([type.rawValue]) + bigEndian(UInt16(message.count)) + message
    }

    init(type: PacketType, message: Data) {
        self.type = type
        self.message = message
    }

    init(decoding body: Data) throws {
        let bytes = [UInt8](body)
        guard bytes.count >= Self.headerSize else { throw FrameError.malformed }
        guard let type = PacketType(rawValue: bytes[0]) else { throw FrameError.unknownType(bytes[0]) }
        let length = Int(bytes[1]) << 8 | Int(bytes[2])
        guard Self.headerSize + length <= bytes.count else { throw FrameError.malformed }
        self.type = type
        message = Data(bytes[Self.headerSize..<Self.headerSize + length])
    }
}

/// What a transport message carries, padded to one size before encryption.
public enum SessionContent: Equatable, Sendable {
    case text(String)

    /// Plaintext size: whatever leaves room for the 16-byte tag in a packet.
    static let paddedSize = SessionPacket.maxMessageSize - 16
    static let headerSize = 3
    /// The most UTF-8 bytes one message can hold.
    public static let maxContentBytes = paddedSize - headerSize

    private static let textType: UInt8 = 1

    func padded() throws -> Data {
        switch self {
        case .text(let string):
            let content = Data(string.utf8)
            guard content.count <= Self.maxContentBytes else { throw FrameError.tooLong }
            var data = Data([Self.textType]) + bigEndian(UInt16(content.count)) + content
            data.append(Data(count: Self.paddedSize - data.count))
            return data
        }
    }

    init(unpadding data: Data) throws {
        let bytes = [UInt8](data)
        guard bytes.count == Self.paddedSize else { throw FrameError.malformed }
        let length = Int(bytes[1]) << 8 | Int(bytes[2])
        guard Self.headerSize + length <= bytes.count else { throw FrameError.malformed }
        let content = Data(bytes[Self.headerSize..<Self.headerSize + length])
        switch bytes[0] {
        case Self.textType:
            guard let string = String(data: content, encoding: .utf8) else { throw FrameError.malformed }
            self = .text(string)
        default:
            throw FrameError.unknownType(bytes[0])
        }
    }
}

private func bigEndian(_ value: UInt16) -> Data {
    Data([UInt8(value >> 8), UInt8(value & 0xFF)])
}

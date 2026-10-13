//
//  PairingPayload.swift
//  PairingKit
//
//  What one phone shows and the other scans. Nothing in it is secret: it is
//  the identity PUBLIC key, the routing address and a label. See
//  Architecture/pairing-workflow.md for what that does and does not protect.
//
//  Text form:   "SCPAIR:" + base64url(bytes), no padding
//  Bytes:       [version = 1][identityPublicKey 32][accountUUID 16]
//               [nameLength 1][displayName, UTF-8, 1...64 bytes]
//               [acknowledgement 8]            optional
//

import Foundation
import CryptoKit

public struct PairingPayload: Equatable, Sendable {

    public static let prefix = "SCPAIR:"
    public static let version: UInt8 = 1
    public static let identityKeyLength = 32
    public static let maxDisplayNameBytes = 64
    public static let acknowledgementLength = 8

    public let identityPublicKey: Data
    public let accountUUID: UUID
    public let displayName: String
    /// "I have read your code": present once the phone showing this code has
    /// scanned another one, and names which. See `acknowledges(_:)`.
    public let acknowledgement: Data?

    /// - Parameter peerIdentityPublicKey: the identity key of the code this
    ///   device has just scanned, if any. The other phone, still watching
    ///   this screen, then learns that the pairing went both ways.
    /// - Throws: `invalidIdentityKey`, `invalidDisplayName`.
    public init(identityPublicKey: Data, accountUUID: UUID, displayName: String,
                acknowledging peerIdentityPublicKey: Data? = nil) throws {
        try self.init(identityPublicKey: identityPublicKey, accountUUID: accountUUID, displayName: displayName,
                      acknowledgement: peerIdentityPublicKey.map(Self.acknowledgement(for:)))
    }

    private init(identityPublicKey: Data, accountUUID: UUID, displayName: String,
                 acknowledgement: Data?) throws {
        guard Self.isUsableKey(identityPublicKey) else { throw PairingError.invalidIdentityKey }
        let name = Self.normalizedName(displayName)
        guard !name.isEmpty else { throw PairingError.invalidDisplayName }
        self.identityPublicKey = identityPublicKey
        self.accountUUID = accountUUID
        self.displayName = name
        self.acknowledgement = acknowledgement
    }

    // MARK: Acknowledgement

    /// Whether the phone showing this code says it has scanned the code of
    /// `identityPublicKey`.
    ///
    /// A CONVENIENCE, NOT A PROOF. The marker is a hash of a public key, so
    /// anyone can produce it. It lets both screens say "done" at the same
    /// moment; whether the other side really stored the contact is settled,
    /// like everything else, by the first session.
    public func acknowledges(_ identityPublicKey: Data) -> Bool {
        acknowledgement == Self.acknowledgement(for: identityPublicKey)
    }

    static func acknowledgement(for identityPublicKey: Data) -> Data {
        Data(SHA256.hash(data: identityPublicKey).prefix(acknowledgementLength))
    }

    // MARK: Encoding

    /// The string to put in the QR code.
    public func encoded() -> String {
        var bytes = Data([Self.version])
        bytes.append(identityPublicKey)
        bytes.append(withUnsafeBytes(of: accountUUID.uuid) { Data($0) })
        let name = Data(displayName.utf8)
        bytes.append(UInt8(name.count))
        bytes.append(name)
        if let acknowledgement { bytes.append(acknowledgement) }
        return Self.prefix + Self.base64URLEncode(bytes)
    }

    // MARK: Decoding

    /// Parses what a scanner read. Everything in `scanned` is untrusted.
    public init(scanned: String) throws {
        let text = scanned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix(Self.prefix) else { throw PairingError.notAPairingCode }
        guard let bytes = Self.base64URLDecode(String(text.dropFirst(Self.prefix.count))),
              let version = bytes.first else {
            throw PairingError.malformed
        }
        guard version == Self.version else { throw PairingError.unsupportedVersion(version) }

        let headerLength = 1 + Self.identityKeyLength + 16 + 1
        guard bytes.count > headerLength else { throw PairingError.malformed }
        let body = [UInt8](bytes)
        let key = Data(body[1 ..< 1 + Self.identityKeyLength])
        let uuidBytes = Array(body[1 + Self.identityKeyLength ..< headerLength - 1])
        let nameLength = Int(body[headerLength - 1])
        let nameEnd = headerLength + nameLength
        // Exact lengths only: no trailing bytes for a later version to hide in.
        guard nameLength >= 1, nameLength <= Self.maxDisplayNameBytes,
              body.count == nameEnd || body.count == nameEnd + Self.acknowledgementLength,
              let rawName = String(bytes: body[headerLength ..< nameEnd], encoding: .utf8) else {
            throw PairingError.malformed
        }
        let acknowledgement = body.count > nameEnd ? Data(body[nameEnd...]) : nil

        let uuid = uuidBytes.withUnsafeBytes { UUID(uuid: $0.loadUnaligned(as: uuid_t.self)) }
        do {
            try self.init(identityPublicKey: key, accountUUID: uuid, displayName: rawName,
                          acknowledgement: acknowledgement)
        } catch PairingError.invalidDisplayName {
            throw PairingError.malformed
        }
    }

    // MARK: Display name

    /// The name as it is sent and stored: no control characters or line
    /// breaks, no surrounding whitespace, at most `maxDisplayNameBytes` of
    /// UTF-8 (cut on a whole character). Applied to scanned names too — a
    /// name is a label chosen by the other side and is shown in our UI.
    public static func normalizedName(_ name: String) -> String {
        let cleaned = String(String.UnicodeScalarView(name.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .lineSeparator, .paragraphSeparator: return false
            default: return true
            }
        })).trimmingCharacters(in: .whitespaces)

        var result = ""
        var byteCount = 0
        for character in cleaned {
            byteCount += character.utf8.count
            guard byteCount <= maxDisplayNameBytes else { break }
            result.append(character)
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Helpers

    /// 32 bytes and not all zero. Any other 32 bytes is accepted here: a key
    /// nobody holds the private half of only yields a contact that can never
    /// complete a session.
    static func isUsableKey(_ key: Data) -> Bool {
        key.count == identityKeyLength && key.contains { $0 != 0 }
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ text: String) -> Data? {
        guard !text.isEmpty,
              text.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
            return nil
        }
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}

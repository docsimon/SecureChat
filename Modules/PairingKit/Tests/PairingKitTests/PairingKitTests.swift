//
//  PairingKitTests.swift
//  PairingKitTests
//

import Foundation
import CoreImage
import Testing
@testable import PairingKit

private func key(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }

private func code(key keyByte: UInt8 = 7,
                  uuid: UUID = UUID(),
                  name: String = "otter-canyon-4417") throws -> String {
    try PairingPayload(identityPublicKey: key(keyByte), accountUUID: uuid, displayName: name).encoded()
}

/// Builds the text form from raw bytes, for codes the encoder would never produce.
private func rawCode(_ bytes: Data) -> String {
    PairingPayload.prefix + bytes.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func rawBytes(version: UInt8 = 1, key keyBytes: Data = key(7), name: Data = Data("Ada".utf8),
                      nameLength: UInt8? = nil, trailing: Data = Data()) -> Data {
    var bytes = Data([version])
    bytes.append(keyBytes)
    bytes.append(withUnsafeBytes(of: UUID().uuid) { Data($0) })
    bytes.append(nameLength ?? UInt8(name.count))
    bytes.append(name)
    bytes.append(trailing)
    return bytes
}

@Suite("PairingPayload")
struct PairingPayloadTests {

    @Test("A code decodes to what was encoded")
    func roundTrip() throws {
        let uuid = UUID()
        let original = try PairingPayload(identityPublicKey: key(0xAB), accountUUID: uuid, displayName: "Zoë 🦦")
        let decoded = try PairingPayload(scanned: original.encoded())
        #expect(decoded == original)
        #expect(decoded.accountUUID == uuid)
        #expect(decoded.displayName == "Zoë 🦦")
    }

    @Test("The text form is the prefix plus URL-safe base64")
    func textForm() throws {
        let text = try code()
        #expect(text.hasPrefix("SCPAIR:"))
        #expect(text.dropFirst(7).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
    }

    @Test("Surrounding whitespace from a paste is ignored")
    func toleratesWhitespace() throws {
        let text = try code()
        #expect(try PairingPayload(scanned: "  \(text)\n") == PairingPayload(scanned: text))
    }

    @Test("Other QR codes are not pairing codes", arguments: ["", "https://example.com", "WIFI:S:home;;", "scpair:abc"])
    func foreignCodes(text: String) {
        #expect(throws: PairingError.notAPairingCode) { try PairingPayload(scanned: text) }
    }

    @Test("A newer version is reported as such")
    func unsupportedVersion() {
        #expect(throws: PairingError.unsupportedVersion(2)) {
            try PairingPayload(scanned: rawCode(rawBytes(version: 2)))
        }
    }

    @Test("Damaged contents are refused")
    func malformed() {
        let cases: [String] = [
            "SCPAIR:",
            "SCPAIR:not base64!",
            rawCode(rawBytes().dropLast(1)),                          // truncated
            rawCode(rawBytes(trailing: Data([0]))),                   // trailing byte
            rawCode(rawBytes(name: Data(), nameLength: 0)),           // empty name
            rawCode(rawBytes(name: Data(repeating: 0x41, count: 65))), // name too long
            rawCode(rawBytes(name: Data([0xFF, 0xFE]))),              // not UTF-8
            rawCode(rawBytes(name: Data("\n\t".utf8))),               // nothing left once cleaned
        ]
        for text in cases {
            #expect(throws: PairingError.malformed) { try PairingPayload(scanned: text) }
        }
    }

    @Test("An all-zero or wrong-size key is refused")
    func invalidKey() {
        #expect(throws: PairingError.invalidIdentityKey) {
            try PairingPayload(scanned: rawCode(rawBytes(key: Data(repeating: 0, count: 32))))
        }
        #expect(throws: PairingError.invalidIdentityKey) {
            try PairingPayload(identityPublicKey: Data(repeating: 1, count: 31), accountUUID: UUID(), displayName: "Ada")
        }
    }

    @Test("A name that is empty once cleaned cannot be sent")
    func emptyName() {
        #expect(throws: PairingError.invalidDisplayName) {
            try PairingPayload(identityPublicKey: key(1), accountUUID: UUID(), displayName: "  \n ")
        }
    }

    @Test("Names lose control characters and surrounding spaces")
    func nameIsCleaned() {
        #expect(PairingPayload.normalizedName("  Ada\nLovelace\u{0007} ") == "AdaLovelace")
        #expect(PairingPayload.normalizedName("Ada Lovelace") == "Ada Lovelace")
    }

    @Test("Long names are cut on a whole character within 64 bytes")
    func nameIsTruncated() {
        let long = String(repeating: "🦦", count: 40)   // 4 bytes each
        let cut = PairingPayload.normalizedName(long)
        #expect(cut == String(repeating: "🦦", count: 16))
        #expect(cut.utf8.count == 64)
    }

    @Test("A scanned name is cleaned as well")
    func scannedNameIsCleaned() throws {
        let payload = try PairingPayload(scanned: rawCode(rawBytes(name: Data("Ada\nB".utf8))))
        #expect(payload.displayName == "AdaB")
    }
}

@Suite("Pairing.evaluate")
struct PairingEvaluateTests {

    let ownKey = key(1)
    let ownUUID = UUID()
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func evaluate(_ text: String, contacts: [PairedContact] = []) throws -> Pairing.Outcome {
        try Pairing.evaluate(scanned: text, ownIdentityPublicKey: ownKey, ownAccountUUID: ownUUID,
                             contacts: contacts, now: now)
    }

    @Test("An unknown code becomes a new contact")
    func newContact() throws {
        let uuid = UUID()
        let outcome = try evaluate(code(key: 7, uuid: uuid, name: "Ada"))
        #expect(outcome == .newContact(PairedContact(identityPublicKey: key(7), accountUUID: uuid,
                                                     displayName: "Ada", pairedAt: now)))
    }

    @Test("Scanning your own code is refused, by key or by account id")
    func ownCode() throws {
        #expect(throws: PairingError.ownCode) { try evaluate(code(key: 1, uuid: ownUUID)) }
        #expect(throws: PairingError.ownCode) { try evaluate(code(key: 1)) }
        #expect(throws: PairingError.ownCode) { try evaluate(code(key: 9, uuid: ownUUID)) }
    }

    @Test("Scanning a stored contact again changes nothing, not even the name")
    func alreadyPaired() throws {
        let uuid = UUID()
        let stored = PairedContact(identityPublicKey: key(7), accountUUID: uuid, displayName: "My name for Ada",
                                   pairedAt: Date(timeIntervalSince1970: 1))
        let outcome = try evaluate(code(key: 7, uuid: uuid, name: "Ada"), contacts: [stored])
        #expect(outcome == .alreadyPaired(stored))
    }

    @Test("A known key with a new account id, or a known account id with a new key, is refused")
    func conflicts() throws {
        let uuid = UUID()
        let stored = PairedContact(identityPublicKey: key(7), accountUUID: uuid, displayName: "Ada", pairedAt: now)
        let other = PairedContact(identityPublicKey: key(8), accountUUID: UUID(), displayName: "Bob", pairedAt: now)
        #expect(throws: PairingError.conflictsWithExistingContact) {
            try evaluate(code(key: 7), contacts: [stored])
        }
        #expect(throws: PairingError.conflictsWithExistingContact) {
            try evaluate(code(key: 9, uuid: uuid), contacts: [stored])
        }
        // Key of one stored contact, account id of another.
        #expect(throws: PairingError.conflictsWithExistingContact) {
            try evaluate(code(key: 7, uuid: other.accountUUID), contacts: [stored, other])
        }
    }

    @Test("A code that does not parse stores nothing")
    func parseErrorsPropagate() {
        #expect(throws: PairingError.notAPairingCode) { try evaluate("https://example.com") }
    }
}

@Suite("PairingQRCode")
struct PairingQRCodeTests {

    @Test("The image reads back as the same code, longest name included")
    func imageRoundTrip() throws {
        let text = try code(name: String(repeating: "🦦", count: 16))
        let image = try #require(PairingQRCode.image(for: text))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let found = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(found == [text])
    }
}

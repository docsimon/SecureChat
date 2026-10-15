//
//  PairingKitTests.swift
//  PairingKitTests
//

import Foundation
import CoreImage
import Testing
@testable import PairingKit

private func key(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }

/// For call sites where a local `key` shadows the function above.
private enum PairingKitTests {
    static func key(_ byte: UInt8) -> Data { Data(repeating: byte, count: 32) }
}

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

    @Test("The acknowledgement survives the round trip and names one key only")
    func acknowledgementRoundTrip() throws {
        let plain = try PairingPayload(identityPublicKey: key(7), accountUUID: UUID(), displayName: "Ada")
        #expect(plain.acknowledgement == nil)
        #expect(!plain.acknowledges(key(1)))

        let marked = try PairingPayload(identityPublicKey: key(7), accountUUID: plain.accountUUID,
                                        displayName: "Ada", acknowledging: key(1))
        let decoded = try PairingPayload(scanned: marked.encoded())
        #expect(decoded == marked)
        #expect(decoded.acknowledges(key(1)))
        #expect(!decoded.acknowledges(key(2)))
        #expect(marked.encoded() != plain.encoded())
    }

    @Test("Only an 8-byte acknowledgement may follow the name")
    func acknowledgementLength() {
        #expect(throws: PairingError.malformed) {
            try PairingPayload(scanned: rawCode(rawBytes(trailing: Data(repeating: 1, count: 7))))
        }
        #expect(throws: PairingError.malformed) {
            try PairingPayload(scanned: rawCode(rawBytes(trailing: Data(repeating: 1, count: 9))))
        }
        #expect(throws: Never.self) {
            try PairingPayload(scanned: rawCode(rawBytes(trailing: Data(repeating: 1, count: 8))))
        }
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

    private func evaluation(_ text: String, contacts: [PairedContact] = []) throws -> Pairing.Evaluation {
        try Pairing.evaluate(scanned: text, ownIdentityPublicKey: ownKey, ownAccountUUID: ownUUID,
                             contacts: contacts, now: now)
    }

    private func evaluate(_ text: String, contacts: [PairedContact] = []) throws -> Pairing.Outcome {
        try evaluation(text, contacts: contacts).outcome
    }

    @Test("A code that acknowledges our key says they scanned us; any other does not")
    func peerHasScannedUs() throws {
        let uuid = UUID()
        func text(acknowledging peer: Data?) throws -> String {
            try PairingPayload(identityPublicKey: key(7), accountUUID: uuid, displayName: "Ada",
                               acknowledging: peer).encoded()
        }
        #expect(try evaluation(text(acknowledging: nil)).peerHasScannedUs == false)
        #expect(try evaluation(text(acknowledging: key(9))).peerHasScannedUs == false)

        let acknowledged = try evaluation(text(acknowledging: ownKey))
        #expect(acknowledged.peerHasScannedUs)
        #expect(acknowledged.contact.identityPublicKey == key(7))

        // The marker does not make it a different contact.
        let stored = try evaluation(text(acknowledging: nil)).contact
        let again = try evaluation(text(acknowledging: ownKey), contacts: [stored])
        #expect(again.outcome == .alreadyPaired(stored))
        #expect(again.peerHasScannedUs)
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
        let text = try PairingPayload(identityPublicKey: key(7), accountUUID: UUID(),
                                      displayName: String(repeating: "🦦", count: 16),
                                      acknowledging: key(1)).encoded()
        let image = try #require(PairingQRCode.image(for: text))
        let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                                               options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        let found = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        #expect(found == [text])
    }
}

@Suite("FaceToFacePairing")
@MainActor
struct FaceToFacePairingTests {

    /// One phone: an identity, a contact list, and the attempt running on it.
    @MainActor
    final class Phone {
        let key: Data
        let uuid = UUID()
        var contacts: [PairedContact] = []
        var storeCount = 0
        private(set) var pairing: FaceToFacePairing!

        init(_ keyByte: UInt8, name: String) {
            key = PairingKitTests.key(keyByte)
            pairing = FaceToFacePairing(
                identityPublicKey: key, accountUUID: uuid, displayName: name,
                contacts: { [unowned self] in self.contacts },
                store: { [unowned self] in self.contacts.append($0); self.storeCount += 1 },
                now: { Date(timeIntervalSince1970: 1_800_000_000) })
        }

        var code: String { pairing.codeToShow! }
    }

    @Test("Two phones facing each other both end up paired both ways")
    func bothWays() throws {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob")

        // A reads B first: saved at once, though B has not acknowledged yet.
        let bob = try #require(a.pairing.scanned(b.code).flatMap { event -> PairedContact? in
            if case .readTheirs(let contact) = event { return contact } else { return nil }
        })
        #expect(bob.identityPublicKey == b.key)
        #expect(a.pairing.progress == .readTheirs(bob))
        #expect(a.contacts == [bob])

        // A's code now carries the marker, so B completes on its first read.
        let event = b.pairing.scanned(a.code)
        let ada = try #require(b.contacts.first)
        #expect(event == .completed(ada))
        #expect(b.pairing.progress == .bothWays(ada))

        // B's code changed in turn; A completes on reading it.
        #expect(a.pairing.scanned(b.code) == .completed(bob))
        #expect(a.pairing.progress == .bothWays(bob))
        #expect(a.contacts == [bob])

        #expect(a.storeCount == 1)
        #expect(b.storeCount == 1)
    }

    @Test("The code stays in view: the same text is acted on once")
    func repeatedText() {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob")
        let text = b.code
        #expect(a.pairing.scanned(text) != nil)
        #expect(a.pairing.scanned(text) == nil)
        #expect(a.storeCount == 1)
    }

    @Test("A marker for someone else does not complete the pairing")
    func foreignAcknowledgement() throws {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob"), c = Phone(3, name: "Cy")
        b.pairing.scanned(c.code)          // B now acknowledges C, not A
        let event = try #require(a.pairing.scanned(b.code))
        guard case .readTheirs = event else {
            Issue.record("expected readTheirs, got \(event)")
            return
        }
    }

    @Test("A refused code is reported, and a good one afterwards still pairs")
    func refusedThenGood() {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob")
        #expect(a.pairing.scanned(a.code) == .refused(.ownCode))
        #expect(a.pairing.progress == .refused(.ownCode))
        #expect(a.pairing.scanned(b.code) != nil)
        #expect(a.contacts.count == 1)
    }

    @Test("Once their code is read, a stray or third code changes nothing")
    func strayCodesAfterRead() {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob"), c = Phone(3, name: "Cy")
        a.pairing.scanned(b.code)
        let progress = a.pairing.progress
        #expect(a.pairing.scanned("https://example.com") == nil)
        #expect(a.pairing.scanned(c.code) == nil)
        #expect(a.pairing.progress == progress)
        #expect(a.contacts.count == 1)
    }

    @Test("An already stored contact completes without being stored again")
    func alreadyStored() {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob")
        a.pairing.scanned(b.code)
        b.pairing.scanned(a.code)
        a.pairing.restart()
        b.pairing.restart()
        #expect(a.pairing.progress == .looking)

        a.pairing.scanned(b.code)
        b.pairing.scanned(a.code)
        a.pairing.scanned(b.code)
        guard case .bothWays = a.pairing.progress, case .bothWays = b.pairing.progress else {
            Issue.record("expected both ways on both phones")
            return
        }
        #expect(a.storeCount == 1)
        #expect(b.storeCount == 1)
    }

    @Test("Nothing more happens after the pairing is complete")
    func finalState() {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob"), c = Phone(3, name: "Cy")
        a.pairing.scanned(b.code)
        b.pairing.scanned(a.code)
        #expect(b.pairing.scanned(c.code) == nil)
        #expect(b.contacts.count == 1)
    }

    @Test("Pulled apart after one read: doing it again completes the other side")
    func oneSidedThenAgain() {
        let a = Phone(1, name: "Ada"), b = Phone(2, name: "Bob")
        a.pairing.scanned(b.code)               // only A read; B has nothing
        #expect(a.contacts.count == 1)
        #expect(b.contacts.isEmpty)

        // Held together again, same attempt on A: B reads A's code, which
        // already says "I have yours", then A reads B's answer.
        #expect(b.pairing.scanned(a.code) != nil)
        #expect(a.pairing.scanned(b.code) != nil)

        #expect(b.contacts.count == 1)
        #expect(a.storeCount == 1)
        guard case .bothWays = a.pairing.progress, case .bothWays = b.pairing.progress else {
            Issue.record("expected both ways on both phones")
            return
        }
    }
}

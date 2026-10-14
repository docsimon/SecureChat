//
//  AttestationEnvironmentHintTests.swift
//  RegistrationKitTests
//
//  Moved from AppAttestTestAppTests on 2026-10-14 with the code it tests.
//

import Foundation
import Testing
import RegistrationKit

// MARK: - AttestationEnvironmentHint
//
// Pure, deterministic CBOR parsing — no Keychain, no App Attest, no device
// dependency. Verified against a REAL Apple attestation object once already
// this session (the cbor.me cross-check), but that was a one-time manual
// confirmation, not something that protects against a future edit breaking
// the parser. These tests build synthetic-but-valid CBOR fixtures (a real
// attestation object isn't something to embed as a fixture — see the
// keyId-sensitivity notes elsewhere in this project) to lock in the actual
// decoding logic.

@Suite("AttestationEnvironmentHint")
struct AttestationEnvironmentHintTests {

    // MARK: Minimal CBOR encoder, test-fixture-only — NOT the same code as
    // the decoder under test. Building fixtures with independent encoding
    // logic is what makes this a real test of the decoder, not a tautology.

    private static func cborHeader(majorType: UInt8, length: Int) -> Data {
        let major = majorType << 5
        if length <= 23 {
            return Data([major | UInt8(length)])
        } else if length <= 255 {
            return Data([major | 24, UInt8(length)])
        } else {
            let len = UInt16(length)
            return Data([major | 25, UInt8(len >> 8), UInt8(len & 0xFF)])
        }
    }

    private static func cborText(_ s: String) -> Data {
        let utf8 = Data(s.utf8)
        return cborHeader(majorType: 3, length: utf8.count) + utf8
    }

    private static func cborBytes(_ bytes: Data) -> Data {
        cborHeader(majorType: 2, length: bytes.count) + bytes
    }

    private static func cborMap(entryCount: Int) -> Data {
        cborHeader(majorType: 5, length: entryCount)
    }

    /// Builds a valid {fmt, attStmt, authData} attestation object, with a
    /// caller-supplied 16-byte aaguid embedded at the correct offset (byte
    /// 37: rpIdHash 32 + flags 1 + counter 4) inside a realistically-shaped
    /// authData.
    private static func makeAttestationObject(aaguid: Data, authDataLength: Int? = nil) -> Data {
        var authData = Data(repeating: 0xAA, count: 32)        // rpIdHash
        authData.append(0x00)                                   // flags
        authData.append(contentsOf: [0x00, 0x00, 0x00, 0x00])   // counter
        authData.append(aaguid)                                 // aaguid, 16 bytes
        authData.append(Data(repeating: 0xBB, count: 10))       // trailing bytes, realism only

        if let authDataLength {
            authData = authData.prefix(authDataLength)
        }

        var object = cborMap(entryCount: 3)
        object += cborText("fmt") + cborText("apple-appattest")
        object += cborText("attStmt") + cborMap(entryCount: 0)
        object += cborText("authData") + cborBytes(authData)
        return object
    }

    @Test("Extracts the real aaguid bytes at the correct offset, hex and ASCII both")
    func extractsAAGUIDAtCorrectOffset() {
        let marker = "appattestdevelop"
        let aaguid = Data(marker.utf8) // exactly 16 bytes
        let object = Self.makeAttestationObject(aaguid: aaguid)

        let result = AttestationEnvironmentHint.describe(object)

        // Computed here, not hand-transcribed — a manual hex transcription
        // of this same string is exactly what broke in the first version of
        // this test (miscounted a byte).
        let expectedHex = aaguid.map { String(format: "%02x", $0) }.joined()
        #expect(result.contains(expectedHex))
        #expect(result.contains("\"\(marker)\""))
    }

    @Test("Classifies the environment from the aaguid alone")
    func classifiesEnvironment() {
        let development = Self.makeAttestationObject(aaguid: Data("appattestdevelop".utf8))
        let production = Self.makeAttestationObject(aaguid: Data("appattest".utf8) + Data(repeating: 0, count: 7))
        // The string one secondhand source claimed for development — must NOT
        // be accepted as development just because it looks plausible.
        let lookalike = Self.makeAttestationObject(aaguid: Data("appattestsandbox".utf8))

        #expect(AttestationEnvironmentHint.environment(of: development) == .development)
        #expect(AttestationEnvironmentHint.environment(of: production) == .production)
        #expect(AttestationEnvironmentHint.environment(of: lookalike) == .unrecognised)
        #expect(AttestationEnvironmentHint.environment(of: Data()) == .unrecognised)
    }

    @Test("Non-printable aaguid bytes render as dots in the ASCII column, not garbage or a crash")
    func nonPrintableBytesRenderAsDots() {
        let nonPrintableCount = 3
        let printableCount = 13 // must sum to 16 (the aaguid's fixed length)
        let aaguid = Data(Array(repeating: 0x00, count: nonPrintableCount)
            + Array(repeating: 0x41, count: printableCount)) // 0x41 = 'A'
        let object = Self.makeAttestationObject(aaguid: aaguid)

        let result = AttestationEnvironmentHint.describe(object)

        // Built the expected string the same way, rather than hand-counting
        // characters in a literal — that's exactly the kind of off-by-one
        // this test exists to catch, not introduce.
        let expectedASCII = String(repeating: ".", count: nonPrintableCount)
            + String(repeating: "A", count: printableCount)
        #expect(result.contains("\"\(expectedASCII)\""))
    }

    @Test("authData shorter than 53 bytes is reported, not crashed on")
    func shortAuthDataReportedCleanly() {
        let aaguid = Data(repeating: 0x41, count: 16)
        // 40 bytes total: not enough to contain a full aaguid at offset 37.
        let object = Self.makeAttestationObject(aaguid: aaguid, authDataLength: 40)

        let result = AttestationEnvironmentHint.describe(object)

        #expect(result.contains("too short"))
        #expect(result.contains("40 bytes"))
    }

    @Test("Missing authData key is reported, not crashed on")
    func missingAuthDataKeyReportedCleanly() {
        var object = Self.cborMap(entryCount: 2)
        object += Self.cborText("fmt") + Self.cborText("apple-appattest")
        object += Self.cborText("attStmt") + Self.cborMap(entryCount: 0)
        // No "authData" key at all.

        let result = AttestationEnvironmentHint.describe(object)

        #expect(result.contains("could not parse"))
    }

    @Test("Truncated/malformed CBOR is reported, not crashed on")
    func truncatedCBORReportedCleanly() {
        let aaguid = Data(repeating: 0x41, count: 16)
        let object = Self.makeAttestationObject(aaguid: aaguid)
        let truncated = object.prefix(object.count / 2) // cut off mid-structure

        let result = AttestationEnvironmentHint.describe(Data(truncated))

        #expect(result.contains("could not parse") || result.contains("too short"))
    }

    @Test("Empty data is reported, not crashed on")
    func emptyDataReportedCleanly() {
        let result = AttestationEnvironmentHint.describe(Data())

        #expect(result.contains("could not parse"))
    }
}

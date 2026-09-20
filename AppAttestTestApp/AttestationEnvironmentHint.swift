//
//  AttestationEnvironmentHint.swift
//  AppAttestTestApp
//
//  Answers "am I actually hitting the App Attest development sandbox?"
//  directly from Apple's own response, rather than trusting configuration
//  alone. The aaguid field inside authData is meant to carry a marker
//  distinguishing development from production — but two secondhand sources
//  disagreed on the exact string ("appattestsandbox" vs "appattestdevelop":
//  one from a web search this session, the other from a comment already in
//  Architecture/AttestHarnessApp.swift, predating this session). Rather than
//  trust either, this decodes the real bytes and shows them — ground truth
//  from your own device, not a guessed marker to search for.
//
//  ⚠️ The CBOR decoding below is intentionally minimal — just enough to
//  walk the top-level {fmt, attStmt, authData} map and skip nested
//  structures generically (RFC 8949's major types), not a general-purpose
//  CBOR library. It bails out to nil on anything unexpected (indefinite-
//  length items) rather than guessing. Do not reuse this for the real
//  server-side verifier — architecture doc §2: use a maintained library,
//  do not hand-roll this. This only has to answer one diagnostic question
//  in a log line.
//

import Foundation

enum AttestationEnvironmentHint {

    static func describe(_ attestationObject: Data) -> String {
        guard let authData = extractAuthData(from: attestationObject) else {
            return "could not parse authData from the attestation object (CBOR shape unexpected — see AttestationEnvironmentHint.swift)"
        }
        // aaguid sits at a fixed offset inside authData:
        // rpIdHash (32 bytes) + flags (1 byte) + counter (4 bytes) = byte 37,
        // then 16 bytes of aaguid.
        guard authData.count >= 53 else {
            return "authData too short to contain an aaguid (\(authData.count) bytes)"
        }
        let start = authData.startIndex + 37
        let aaguid = authData.subdata(in: start..<(start + 16))
        let hex = aaguid.map { String(format: "%02x", $0) }.joined()
        let ascii = String(aaguid.map { byte -> Character in
            (32...126).contains(byte) ? Character(UnicodeScalar(byte)) : "."
        })
        return "aaguid = \(hex)  (\"\(ascii)\")"
    }

    // MARK: - Minimal CBOR walk

    /// Walks the top-level definite-length map looking for the "authData"
    /// key, skipping every other key's value generically.
    private static func extractAuthData(from data: Data) -> Data? {
        var offset = 0
        guard let (majorType, pairCount, headerSize) = readHeader(data, offset), majorType == 5 else {
            return nil
        }
        offset += headerSize
        for _ in 0..<pairCount {
            guard let (key, afterKey) = readStringBytes(data, offset) else { return nil }
            if String(decoding: key, as: UTF8.self) == "authData" {
                return readStringBytes(data, afterKey)?.bytes
            }
            guard let afterValue = skip(data, afterKey) else { return nil }
            offset = afterValue
        }
        return nil
    }

    /// Decodes a CBOR item's header: major type (top 3 bits), and its
    /// length/value (bottom 5 bits, possibly extended into following bytes
    /// per RFC 8949 §3). Returns nil for indefinite-length items (additional
    /// info 31) or reserved values — this decoder doesn't need to support
    /// them for Apple's attestation object shape.
    private static func readHeader(_ data: Data, _ offset: Int) -> (majorType: Int, value: Int, headerSize: Int)? {
        guard offset < data.count else { return nil }
        let first = data[data.startIndex + offset]
        let majorType = Int(first >> 5)
        let additional = first & 0x1F
        switch additional {
        case 0...23:
            return (majorType, Int(additional), 1)
        case 24:
            guard offset + 1 < data.count else { return nil }
            return (majorType, Int(data[data.startIndex + offset + 1]), 2)
        case 25:
            guard offset + 2 < data.count else { return nil }
            let b0 = Int(data[data.startIndex + offset + 1])
            let b1 = Int(data[data.startIndex + offset + 2])
            return (majorType, (b0 << 8) | b1, 3)
        case 26:
            guard offset + 4 < data.count else { return nil }
            var value = 0
            for i in 1...4 { value = (value << 8) | Int(data[data.startIndex + offset + i]) }
            return (majorType, value, 5)
        case 27:
            guard offset + 8 < data.count else { return nil }
            var value = 0
            for i in 1...8 { value = (value << 8) | Int(data[data.startIndex + offset + i]) }
            return (majorType, value, 9)
        default:
            return nil
        }
    }

    /// Reads a byte string or text string's raw content, returning the
    /// content and the offset immediately after it.
    private static func readStringBytes(_ data: Data, _ offset: Int) -> (bytes: Data, next: Int)? {
        guard let (majorType, length, headerSize) = readHeader(data, offset),
              majorType == 2 || majorType == 3 else { return nil }
        let start = offset + headerSize
        let end = start + length
        guard end <= data.count else { return nil }
        return (data.subdata(in: (data.startIndex + start)..<(data.startIndex + end)), end)
    }

    /// Advances past one CBOR item without decoding its content, recursing
    /// into arrays/maps/tags — needed to skip over "fmt" and the nested
    /// "attStmt" map (which contains an array of certificates and a byte
    /// string) to reach "authData".
    private static func skip(_ data: Data, _ offset: Int) -> Int? {
        guard let (majorType, length, headerSize) = readHeader(data, offset) else { return nil }
        var next = offset + headerSize
        switch majorType {
        case 0, 1, 7:
            return next
        case 2, 3:
            next += length
            return next <= data.count ? next : nil
        case 4:
            for _ in 0..<length {
                guard let n = skip(data, next) else { return nil }
                next = n
            }
            return next
        case 5:
            for _ in 0..<length {
                guard let afterKey = skip(data, next) else { return nil }
                guard let afterValue = skip(data, afterKey) else { return nil }
                next = afterValue
            }
            return next
        case 6:
            return skip(data, next)
        default:
            return nil
        }
    }
}

//
//  AttestationEnvironmentHint.swift
//  AppAttestTestApp
//
//  Answers "am I actually hitting the App Attest development sandbox?"
//  directly from Apple's own response, rather than trusting configuration
//  alone. Confirmed via web search this session: a development-environment
//  attestation is tagged with aaguid "appattestsandbox" inside authData,
//  specifically so server code (and, here, a diagnostic) can tell.
//
//  ⚠️ NOT a real parser. The aaguid sits at a fixed 16-byte offset inside
//  authData (rpIdHash 32 + flags 1 + counter 4 = byte 37), reachable only by
//  decoding the surrounding CBOR structure properly. This skips that and
//  scans the raw bytes for the marker directly — fine for a log line where
//  the worst case is a wrong string, not something to reuse for the real
//  server verifier (architecture doc §2: use a maintained library, do not
//  hand-roll this).
//

import Foundation

enum AttestationEnvironmentHint {
    private static let sandboxMarker = Data("appattestsandbox".utf8)

    static func describe(_ attestationObject: Data) -> String {
        if attestationObject.range(of: sandboxMarker) != nil {
            return "development (aaguid: appattestsandbox)"
        }
        return "no sandbox marker found — unexpected on a real device dev build; check the entitlement if this shows up"
    }
}

//
//  TransportEvent.swift
//  RegistrationKit
//
//  What the Auth Server clients report as they work — for a log or a debug
//  UI. Nothing here drives behaviour.
//

import Foundation

/// Deliberately does NOT expose `AttestationSubmission.keyId` through this
/// event type at all — not even truncated. `keyId` is a real, persistent
/// App Attest key identifier, and architecture doc §10 is explicit that it
/// must never reach a log. Making that structurally impossible (rather than
/// "remember not to log it") is the point of this enum, not a style choice.
public enum TransportEvent: Sendable {
    case challengeFetched(byteCount: Int)
    case submitted(accountUUID: String)
    /// Session token deliberately NOT included, even truncated — it's a live
    /// credential, same reasoning as never logging keyId.
    case sessionOpened(tokenByteCount: Int)
    /// `statusCode == nil` means the request never got an HTTP response at
    /// all (URLSession itself threw — no connection, DNS failure, Local
    /// Network permission denied). A real status code means the server WAS
    /// reached and responded with a rejection — a completely different
    /// failure class from "couldn't reach it." See `AuthServerRequest.swift`'s
    /// `performAuthServerRequest` for why this distinction matters.
    case requestFailed(endpoint: String, statusCode: Int?, detail: String)
}

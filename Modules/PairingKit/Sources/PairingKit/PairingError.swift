//
//  PairingError.swift
//  PairingKit
//

import Foundation

/// Why a code could not be built or a scanned code was refused.
public enum PairingError: Error, Equatable, Sendable {
    /// A QR code, but not one of ours (a URL, a Wi-Fi code, ...).
    case notAPairingCode
    /// One of ours, from a version of the app this one does not understand.
    case unsupportedVersion(UInt8)
    /// Ours and a known version, but the contents do not parse.
    case malformed
    /// Not a usable X25519 public key.
    case invalidIdentityKey
    /// Empty once cleaned up, see `PairingPayload.normalizedName`.
    case invalidDisplayName
    /// The user scanned their own code.
    case ownCode
    /// The scanned identity key or account id is already stored, but paired
    /// with a different counterpart. Under the v1 rules the two always change
    /// together, so this is never a legitimate re-pairing.
    case conflictsWithExistingContact
}

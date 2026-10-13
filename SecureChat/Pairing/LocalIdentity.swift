//
//  LocalIdentity.swift
//  SecureChat
//
//  What this device puts in its pairing code: the identity public key and
//  the account id it registered with. PairingKit is handed these; it never
//  loads them itself.
//

import Foundation
import CryptoKit
import RegistrationKit

struct LocalIdentity: Equatable {
    let identityPublicKey: Data
    let accountUUID: UUID
}

enum LocalIdentityError: Error {
    /// No identity key or no account id: this device has not registered.
    case notRegistered
}

struct LocalIdentityProvider {

#if DEBUG
    /// Debug builds only. Debug runs skip registration
    /// (`RegistrationViewModel.assumesRegistered`), so there is no identity
    /// key and no account id to pair with. When true, a local stand-in is
    /// used instead. Pairing needs no server, so nothing else has to know.
    var usesDebugIdentity = false
#endif

    func load() throws -> LocalIdentity {
#if DEBUG
        if usesDebugIdentity { return DebugLocalIdentity.loadOrCreate() }
#endif
        guard let key = try IdentityKeyStore.loadExisting(),
              let uuid = RegisteredAccountStore.current.flatMap(UUID.init(uuidString:)) else {
            throw LocalIdentityError.notRegistered
        }
        return LocalIdentity(identityPublicKey: key.publicKey.rawRepresentation, accountUUID: uuid)
    }
}

#if DEBUG
/// A made-up identity for Debug runs that skipped registration. The account
/// id is known to no server. Kept in UserDefaults, away from the Keychain
/// items the real registration owns, so the two can never be confused; the
/// private key is kept because sessions will need it.
enum DebugLocalIdentity {
    private static let keyName = "debug.localIdentity.privateKey"
    private static let uuidName = "debug.localIdentity.accountUUID"

    static func loadOrCreate(defaults: UserDefaults = .standard) -> LocalIdentity {
        if let raw = defaults.data(forKey: keyName),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw),
           let uuid = defaults.string(forKey: uuidName).flatMap(UUID.init(uuidString:)) {
            return LocalIdentity(identityPublicKey: key.publicKey.rawRepresentation, accountUUID: uuid)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        let uuid = UUID()
        defaults.set(key.rawRepresentation, forKey: keyName)
        defaults.set(uuid.uuidString, forKey: uuidName)
        return LocalIdentity(identityPublicKey: key.publicKey.rawRepresentation, accountUUID: uuid)
    }
}
#endif

/// The name this user gives to the people they pair with. There is no
/// default yet (the word-triple in architecture-decisions.md §7 needs a
/// wordlist that does not exist), so pairing asks for it once.
struct ProfileStore {
    private static let key = "profile.displayName"
    var defaults: UserDefaults = .standard

    var displayName: String? {
        get { defaults.string(forKey: Self.key) }
        nonmutating set { defaults.set(newValue, forKey: Self.key) }
    }
}

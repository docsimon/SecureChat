//
//  LocalIdentity.swift
//  SecureChat
//
//  What this device puts in its pairing code: the identity public key and
//  the account id it registered with. Sessions also get the private key.
//  PairingKit and SessionKit are handed these; they never load them.
//

import Foundation
import CryptoKit
import RegistrationKit

struct LocalIdentity: Equatable {
    let identityPublicKey: Data
    let accountUUID: UUID
}

/// What sessions need: the identity PRIVATE key (the Noise static key) and
/// the account id the relay knows this device by. A separate type, so the
/// pairing path never holds the private key.
struct SessionIdentity {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let accountUUID: UUID
}

enum LocalIdentityError: Error {
    /// No identity key or no account id: this device has not registered.
    case notRegistered
}

struct LocalIdentityProvider {

    /// Where registration left the identity key and the account id. The
    /// app uses the defaults; tests pass the stores registration wrote to.
    var identityStore: IdentityKeyStore = .live
    var accountStore: RegisteredAccountStore = .live

#if DEBUG
    /// Debug builds only. Debug runs skip registration
    /// (`RegistrationViewModel.assumesRegistered`), so there is no identity
    /// key and no account id to pair with. When true, a local stand-in is
    /// used instead. Pairing needs no server, so nothing else has to know.
    var usesDebugIdentity = false
#endif

    func load() throws -> LocalIdentity {
        let identity = try loadForSessions()
        return LocalIdentity(identityPublicKey: identity.privateKey.publicKey.rawRepresentation,
                             accountUUID: identity.accountUUID)
    }

    func loadForSessions() throws -> SessionIdentity {
#if DEBUG
        if usesDebugIdentity { return DebugLocalIdentity.loadOrCreateForSessions() }
#endif
        guard let key = try identityStore.loadExisting(),
              let uuid = accountStore.current.flatMap(UUID.init(uuidString:)) else {
            throw LocalIdentityError.notRegistered
        }
        return SessionIdentity(privateKey: key, accountUUID: uuid)
    }
}

#if DEBUG
/// A made-up identity for Debug runs that skipped registration. The account
/// id is known to no server. Kept in UserDefaults, away from the Keychain
/// items the real registration owns, so the two can never be confused. The
/// relay knows this account only through its development flag.
enum DebugLocalIdentity {
    private static let keyName = "debug.localIdentity.privateKey"
    private static let uuidName = "debug.localIdentity.accountUUID"

    static func loadOrCreate(defaults: UserDefaults = .standard) -> LocalIdentity {
        let identity = loadOrCreateForSessions(defaults: defaults)
        return LocalIdentity(identityPublicKey: identity.privateKey.publicKey.rawRepresentation,
                             accountUUID: identity.accountUUID)
    }

    static func loadOrCreateForSessions(defaults: UserDefaults = .standard) -> SessionIdentity {
        if let raw = defaults.data(forKey: keyName),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw),
           let uuid = defaults.string(forKey: uuidName).flatMap(UUID.init(uuidString:)) {
            return SessionIdentity(privateKey: key, accountUUID: uuid)
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        let uuid = UUID()
        defaults.set(key.rawRepresentation, forKey: keyName)
        defaults.set(uuid.uuidString, forKey: uuidName)
        return SessionIdentity(privateKey: key, accountUUID: uuid)
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

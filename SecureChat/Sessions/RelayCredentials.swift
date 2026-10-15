//
//  RelayCredentials.swift
//  SecureChat
//
//  What the relay is shown at connect (session-workflow.md, "Relay"): a
//  session token from the Auth Server for a registered device, fetched
//  fresh for every connection (tokens last 15 minutes); or, in Debug runs
//  that skipped registration, the account id the development flag accepts.
//

import Foundation
import RegistrationKit
import SessionKit

struct RelayCredentials {

    /// Signs with the App Attest key: a local Secure Enclave signature,
    /// no call to Apple.
    let sessionClient: SessionClient

#if DEBUG
    /// Debug builds only, set with `LocalIdentityProvider.usesDebugIdentity`:
    /// the Auth Server does not know the debug account, so there is no
    /// token to get.
    var usesDevelopmentAccount = false
#endif

    func credential(for identity: SessionIdentity) async throws -> RelayClient.Credential {
#if DEBUG
        if usesDevelopmentAccount { return .developmentAccount(identity.accountUUID) }
#endif
        let token = try await sessionClient.openSession(accountUuid: identity.accountUUID.uuidString.lowercased())
        return .sessionToken(token)
    }
}

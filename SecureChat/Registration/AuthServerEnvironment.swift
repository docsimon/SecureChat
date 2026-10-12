//
//  AuthServerEnvironment.swift
//  SecureChat
//
//  Which Auth Server this build talks to.
//

import Foundation
import RegistrationKit

enum AuthServerEnvironment {
#if DEBUG
    /// The development server on the Mac — the same one the AppAttestTestApp
    /// harness uses. Plain HTTP on the LAN, reachable only because of the
    /// local-networking exception in Debug-Info.plist (Debug builds only).
    static let baseURL = AuthServerConfig.localDevelopmentURL
#else
    // Deliberate. A Release build must never ship pointing at a developer's
    // Mac, and there is no production Auth Server address yet. Supply one
    // here (HTTPS) when it exists.
    #error("SecureChat has no production Auth Server address yet — see AuthServerEnvironment.swift")
#endif
}

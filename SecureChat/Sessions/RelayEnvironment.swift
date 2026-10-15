//
//  RelayEnvironment.swift
//  SecureChat
//
//  Which relay this build talks to.
//

import Foundation
import RegistrationKit

enum RelayEnvironment {
#if DEBUG
    /// The development relay, next to the Auth Server on the Mac
    /// (`docker compose up` in AuthServer/): same host, port 8081. Plain ws
    /// on the LAN, allowed by Debug-Info.plist only.
    static let url: URL = {
        var components = URLComponents(url: AuthServerConfig.localDevelopmentURL, resolvingAgainstBaseURL: false)!
        components.scheme = "ws"
        components.port = 8081
        components.path = "/relay"
        return components.url!
    }()
#else
    // Deliberate, as in AuthServerEnvironment: no production relay exists
    // yet. Supply one here (wss) when it does.
    #error("SecureChat has no production relay address yet — see RelayEnvironment.swift")
#endif
}

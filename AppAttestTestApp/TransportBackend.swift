//
//  TransportBackend.swift
//  AppAttestTestApp
//
//  Debug-only setting: which server (if any) the harness talks to. Lets you
//  compare behavior across backends — the built-in mock, the local Docker
//  instance, or any other URL (a staging/cloud deployment later) — without
//  touching code. Persisted in UserDefaults, not Keychain: this is a dev
//  tooling preference, not device state that needs to survive a real app
//  deletion the way the identity key or attestation state does.
//

import Foundation

enum TransportBackend: Equatable {
    case mock
    case localDocker
    case custom(URL)

    private static let kindKey = "harness.transportBackend.kind"
    private static let customURLKey = "harness.transportBackend.customURL"

    /// Defaults to `.localDocker`, NOT `.mock` — matching the behavior this
    /// setting is being added on top of. A default of `.mock` here would
    /// silently regress every existing install back to the fake transport
    /// the moment this shipped, with no explicit choice involved.
    static var current: TransportBackend {
        get {
            let defaults = UserDefaults.standard
            switch defaults.string(forKey: kindKey) {
            case "mock":
                return .mock
            case "custom":
                if let raw = defaults.string(forKey: customURLKey), let url = URL(string: raw) {
                    return .custom(url)
                }
                return .localDocker
            default:
                return .localDocker
            }
        }
        set {
            let defaults = UserDefaults.standard
            switch newValue {
            case .mock:
                defaults.set("mock", forKey: kindKey)
            case .localDocker:
                defaults.set("localDocker", forKey: kindKey)
            case .custom(let url):
                defaults.set("custom", forKey: kindKey)
                defaults.set(url.absoluteString, forKey: customURLKey)
            }
        }
    }

    var displayName: String {
        switch self {
        case .mock: return "Mock (no network)"
        case .localDocker: return "Local Docker"
        case .custom(let url): return "Custom (\(url.absoluteString))"
        }
    }
}

//
//  SessionTestAppApp.swift
//  SessionTestApp
//
//  The sessions harness (Architecture/session-workflow.md). Two Simulators,
//  or a Simulator and a phone, open Noise KK sessions through the relay with
//  throwaway identities. Never touches App Attest, the Auth Server or the
//  Keychain: the relay must run with RELAY_DEV_CLAIMED_ACCOUNTS=true.
//

import SwiftUI

@main
struct SessionTestAppApp: App {
    @StateObject private var model = SessionHarnessModel()

    var body: some Scene {
        WindowGroup {
            SessionHarnessView(model: model)
        }
    }
}

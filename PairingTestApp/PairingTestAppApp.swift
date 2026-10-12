//
//  PairingTestAppApp.swift
//  PairingTestApp
//
//  Harness for PairingKit: in-person pairing by mutual QR scan, in isolation
//  from registration, the servers and the rest of SecureChat
//  (Architecture/pairing-workflow.md).
//

import SwiftUI

@main
struct PairingTestAppApp: App {
    var body: some Scene {
        WindowGroup {
            PairingHarnessView()
        }
    }
}

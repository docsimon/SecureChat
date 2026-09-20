//
//  AppAttestTestAppApp.swift
//  AppAttestTestApp
//
//  Created by doc on 03/09/2026.
//

import SwiftUI

@main
struct AppAttestTestAppApp: App {
    var body: some Scene {
        WindowGroup {
            // TEMPORARY: previewing the guided-sequence UX redesign with fake
            // data (MockHarnessFlowView/MockHarnessFlowModel — no AppAttestKit
            // import, no real Apple call). The working real harness is still
            // intact in HarnessView/HarnessModel; swap back to HarnessView()
            // here once the design is approved and wired for real.
            MockHarnessFlowView()
        }
    }
}

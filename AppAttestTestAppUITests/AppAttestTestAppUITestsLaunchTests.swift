//
//  AppAttestTestAppUITestsLaunchTests.swift
//  AppAttestTestAppUITests
//
//  Created by doc on 03/09/2026.
//

import XCTest

final class AppAttestTestAppUITestsLaunchTests: XCTestCase {

    // Was `true` (default Xcode boilerplate) — ran this same test 4x per
    // invocation for a project with only one configuration, no real signal
    // gained. Simulator/runner cold-start overhead (~150s the first time)
    // pushed the combined cost of running the full AppAttestTestApp test
    // plan over its timeout; 1 run instead of 4 directly cuts that risk.
    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        // Insert steps here to perform after app launch but before taking a screenshot,
        // such as logging into a test account or navigating somewhere in the app
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

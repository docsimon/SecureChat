// swift-tools-version: 5.9
import PackageDescription

// Encrypted sessions between paired phones (Architecture/session-workflow.md):
// the Noise KK handshake, the fixed-size frame format, the per-peer session
// state, and the WebSocket client for the relay.
//
// A package so that the real app and the SessionTestApp harness compile THE
// SAME code. No dependencies: Noise is written on CryptoKit and checked
// against the published test vector. Like PairingKit it never loads keys
// itself; it is handed the identity key and the contacts.
//
// iOS 16, matching PairingKit, so the harness can run on the iPhone X.
let package = Package(
    name: "SessionKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "SessionKit", targets: ["SessionKit"])
    ],
    targets: [
        .target(
            name: "SessionKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "SessionKitTests",
            dependencies: ["SessionKit"]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// In-person pairing by mutual QR scan (Architecture/pairing-workflow.md):
// the code each phone shows, the checks run on a scanned code, the contact
// record that results, and the camera view that reads a code.
//
// A package, not files inside an app target, so that the real app and the
// PairingTestApp harness compile THE SAME code.
//
// No dependencies, and none on RegistrationKit on purpose: pairing is handed
// the identity public key and the account id, it never loads them. That is
// what lets the harness pair with a throwaway identity and never touch
// App Attest.
//
// iOS 16, one below the other packages: lowered on 2026-10-13 so the
// face-to-face test can run on an older phone (worst-case front camera).
// Nothing here needs 17. Raise it to match the app once the floor is decided.
let package = Package(
    name: "PairingKit",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "PairingKit", targets: ["PairingKit"])
    ],
    targets: [
        .target(
            name: "PairingKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "PairingKitTests",
            dependencies: ["PairingKit"]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

// The app-owned half of registration: everything between AppAttestKit and
// the Auth Server — the transport, the session client, the identity key, the
// stored account id, and the first-launch purge.
//
// It is a package, not files inside an app target, so that the real app and
// the AppAttestTestApp harness compile THE SAME code. A harness that carried
// its own copies would be testing something that never ships.
let package = Package(
    name: "RegistrationKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "RegistrationKit", targets: ["RegistrationKit"])
    ],
    dependencies: [
        .package(path: "../AppAttestKit")
    ],
    targets: [
        .target(
            name: "RegistrationKit",
            dependencies: ["AppAttestKit"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "RegistrationKitTests",
            dependencies: ["RegistrationKit"]
        )
    ]
)

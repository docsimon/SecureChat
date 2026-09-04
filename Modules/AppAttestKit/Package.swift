// swift-tools-version: 5.9
import PackageDescription

// The iOS floor lives HERE, not in per-type `@available` annotations.
// Annotations spread virally to every call site; the manifest states it once.
//
// iOS 17, not 14. App Attest itself is 14+, so the module does not REQUIRE this —
// it is a deliberate choice to match the app (which already uses @Observable,
// 17+) and to unlock Swift Testing. There is no second app to preserve
// portability for; see module doc §11.
let package = Package(
    name: "AppAttestKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "AppAttestKit", targets: ["AppAttestKit"])
    ],
    targets: [
        .target(
            name: "AppAttestKit",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(
            name: "AppAttestKitTests",
            dependencies: ["AppAttestKit"]
        )
    ]
)

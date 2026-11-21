// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "CaloScanCore",
    defaultLocalization: "it",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CaloScanCore", targets: ["CaloScanCore"])
    ],
    targets: [
        .target(
            name: "CaloScanCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        .testTarget(name: "CaloScanCoreTests", dependencies: ["CaloScanCore"])
    ]
)

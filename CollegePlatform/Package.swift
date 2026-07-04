// swift-tools-version: 6.0
// Shared platform types: integration health, calendar change messaging (ADR 004).

import PackageDescription

let package = Package(
    name: "CollegePlatform",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CollegePlatform", targets: ["CollegePlatform"]),
    ],
    targets: [
        .target(name: "CollegePlatform"),
        .testTarget(
            name: "CollegePlatformTests",
            dependencies: ["CollegePlatform"]
        ),
    ]
)

// swift-tools-version: 6.0
// Documents intended platform ↔ feature edges for ADR 004 enforcement.

import PackageDescription

let package = Package(
    name: "CollegePlatformBoundary",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CollegePlatformBoundary", targets: ["CollegePlatformBoundary"]),
    ],
    dependencies: [
        .package(path: "../../CollegePlatform"),
    ],
    targets: [
        .target(
            name: "CollegePlatformBoundary",
            dependencies: [
                .product(name: "CollegePlatform", package: "CollegePlatform"),
            ]
        ),
    ]
)

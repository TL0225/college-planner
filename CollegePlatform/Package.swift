// swift-tools-version: 6.0

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
        .target(
            name: "CollegePlatform",
            dependencies: []
        ),
        .testTarget(
            name: "CollegePlatformTests",
            dependencies: ["CollegePlatform"]
        ),
    ]
)

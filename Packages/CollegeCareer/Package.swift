// swift-tools-version: 6.0
// ADR 004 Phase 2c — Career feature extraction (Layer 1 + scene state).

import PackageDescription

let package = Package(
    name: "CollegeCareer",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CollegeCareer", targets: ["CollegeCareer"]),
    ],
    dependencies: [
        .package(path: "../../CollegePlatform"),
    ],
    targets: [
        .target(
            name: "CollegeCareer",
            dependencies: [
                .product(name: "CollegePlatform", package: "CollegePlatform"),
            ]
        ),
        .testTarget(
            name: "CollegeCareerTests",
            dependencies: ["CollegeCareer"]
        ),
    ]
)

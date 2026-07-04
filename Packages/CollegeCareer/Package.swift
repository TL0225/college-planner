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
        .package(path: "../CollegeDesignSystem"),
    ],
    targets: [
        .target(
            name: "CollegeCareer",
            dependencies: [
                .product(name: "CollegePlatform", package: "CollegePlatform"),
                .product(name: "CollegeDesignSystem", package: "CollegeDesignSystem"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "CollegeCareerTests",
            dependencies: ["CollegeCareer"]
        ),
    ]
)

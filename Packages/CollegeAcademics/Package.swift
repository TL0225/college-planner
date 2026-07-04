// swift-tools-version: 6.0
// ADR 004 Phase 2b — Academics feature extraction (Layer 1 + scene state).

import PackageDescription

let package = Package(
    name: "CollegeAcademics",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CollegeAcademics", targets: ["CollegeAcademics"]),
    ],
    dependencies: [
        .package(path: "../../CollegePlatform"),
        .package(path: "../CollegeDesignSystem"),
    ],
    targets: [
        .target(
            name: "CollegeAcademics",
            dependencies: [
                .product(name: "CollegePlatform", package: "CollegePlatform"),
                .product(name: "CollegeDesignSystem", package: "CollegeDesignSystem"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "CollegeAcademicsTests",
            dependencies: ["CollegeAcademics"]
        ),
    ]
)

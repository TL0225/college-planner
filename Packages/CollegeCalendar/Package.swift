// swift-tools-version: 6.0
// ADR 004 Phase 2 — Calendar feature extraction scaffold.
// Not wired into College.xcodeproj yet; validates dependency edges only.

import PackageDescription

let package = Package(
    name: "CollegeCalendar",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CollegeCalendar", targets: ["CollegeCalendar"]),
    ],
    dependencies: [
        .package(path: "../../CollegePlatform"),
    ],
    targets: [
        .target(
            name: "CollegeCalendar",
            dependencies: [
                .product(name: "CollegePlatform", package: "CollegePlatform"),
            ]
        ),
        .testTarget(
            name: "CollegeCalendarTests",
            dependencies: ["CollegeCalendar"]
        ),
    ]
)

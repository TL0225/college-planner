// swift-tools-version: 6.0
// ADR 004 Phase 2a — Calendar feature extraction (Layers 1–4).

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
            ],
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .linkedFramework("UserNotifications"),
            ]
        ),
        .testTarget(
            name: "CollegeCalendarTests",
            dependencies: ["CollegeCalendar"]
        ),
    ]
)

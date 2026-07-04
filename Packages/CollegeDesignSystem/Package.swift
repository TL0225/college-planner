// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CollegeDesignSystem",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "CollegeDesignSystem", targets: ["CollegeDesignSystem"]),
    ],
    targets: [
        .target(
            name: "CollegeDesignSystem",
            resources: [
                .process("Resources/Colors.xcassets"),
            ]
        ),
    ]
)

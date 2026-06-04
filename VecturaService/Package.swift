// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "VecturaService",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
    ],
    products: [
        .library(name: "VecturaService", targets: ["VecturaService"]),
    ],
    dependencies: [
        .package(url: "https://github.com/rryam/VecturaMLXKit.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "VecturaService",
            dependencies: [
                .product(name: "VecturaMLXKit", package: "VecturaMLXKit"),
            ]
        ),
    ]
)

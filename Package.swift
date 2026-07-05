// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "MobileVLCKit",
    platforms: [
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "MobileVLCKit",
            targets: ["MobileVLCKit"]
        ),
    ],
    dependencies: [],
    targets: [
        .binaryTarget(name: "MobileVLCKit", path: "MobileVLCKit.xcframework"),
    ]
)

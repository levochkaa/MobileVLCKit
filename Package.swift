// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MobileVLCKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "MobileVLCKit",
            targets: ["MobileVLCKit"]),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // .package(url: /* package url */, from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .binaryTarget(
            name: "MobileVLCKit",
            url: "https://instaply-public-libs.s3.eu-west-1.amazonaws.com/ios/MobileVLCKit.xcframework.zip",
            checksum: "4a2bf225beef946a75b33e1854c300382091e5c8e28d1bcff47c2ce74a90a67d"
        )
//        .target(
//            name: "MobileVLCKit",
//            dependencies: []),
//        .testTarget(
//            name: "MobileVLCKitTests",
//            dependencies: ["MobileVLCKit"]),
    ]
)

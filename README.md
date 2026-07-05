# MobileVLCKit

A Swift Package Manager wrapper for the official VideoLAN MobileVLCKit
binary framework.

This package currently tracks **MobileVLCKit 3.7.3**. VideoLAN still does
not publish native Swift Package Manager support for VLCKit; their official
distribution remains CocoaPods/Carthage binaries.

## Installation

Add this package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/levochkaa/MobileVLCKit.git", from: "3.7.3"),
]
```

Then add the product to your target:

```swift
.product(name: "MobileVLCKit", package: "MobileVLCKit")
```

## Updating

Run the update script from the repository root:

```sh
scripts/update-mobilevlckit.sh latest
```

You can also pin a specific official VideoLAN binary version:

```sh
scripts/update-mobilevlckit.sh 3.7.3
```

The script downloads the official VideoLAN MobileVLCKit tarball, extracts the
included `MobileVLCKit.xcframework`, removes legacy 32-bit architectures, and
replaces the local binary target with an iOS-only SPM-ready xcframework.

Upstream SPM tracking issue:
https://code.videolan.org/videolan/VLCKit/-/issues/302

// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-peek-kit",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "PeekKit", targets: ["PeekKit"]),
    ],
    targets: [
        .target(name: "PeekKit"),
        .testTarget(name: "PeekKitTests", dependencies: ["PeekKit"]),
    ]
)

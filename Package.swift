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
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
    ],
    targets: [
        .target(
            name: "PeekKit",
            dependencies: [.product(name: "CoreXLSX", package: "CoreXLSX")]
        ),
        .testTarget(
            name: "PeekKitTests",
            dependencies: ["PeekKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

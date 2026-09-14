// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-peek-kit",
    // macOS 14, not 26. Nothing here is gated on a recent framework — there is not one
    // `@available` in the package — so the higher floor was costing every consumer
    // compatibility in exchange for nothing. Verified by building and running all 82 tests
    // against 14 before lowering it.
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PeekKit", targets: ["PeekKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/CoreOffice/CoreXLSX.git", from: "0.14.2"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "PeekKit",
            dependencies: [
                .product(name: "CoreXLSX", package: "CoreXLSX"),
                .product(name: "Yams", package: "Yams"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
        .testTarget(
            name: "PeekKitTests",
            dependencies: ["PeekKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)

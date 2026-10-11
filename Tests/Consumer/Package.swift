// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AstronomyKitConsumer",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "AstronomyKit", path: "../..")],
    targets: [
        .executableTarget(
            name: "AstronomyKitConsumer",
            dependencies: [.product(name: "AstronomyKit", package: "AstronomyKit")]
        )
    ]
)

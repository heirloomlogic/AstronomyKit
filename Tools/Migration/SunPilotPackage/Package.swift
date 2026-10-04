// swift-tools-version: 6.0

import PackageDescription

// Materialized only in an isolated workspace by Scripts/migration/sun_pilot.py.
let package = Package(
    name: "AstronomySunPilot",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "AstronomySunPilotRunner", targets: ["AstronomySunPilotRunner"]),
        .executable(name: "AstronomyRSSMinimalSwift", targets: ["AstronomyRSSMinimalSwift"]),
        .executable(name: "AstronomyRSSFoundationOnly", targets: ["AstronomyRSSFoundationOnly"]),
        .executable(name: "AstronomyRSSModelLinked", targets: ["AstronomyRSSModelLinked"]),
    ],
    targets: [
        .target(
            name: "CLibAstronomy", path: "Sources/CLibAstronomy", publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include")]),
        .target(name: "AstronomyPolynomialMercuryPrototype"),
        .target(name: "AstronomyPolynomialVenusPrototype"),
        .target(name: "AstronomyPolynomialEarthPrototype"),
        .target(name: "AstronomyPolynomialMarsPrototype"),
        .target(name: "AstronomyPolynomialJupiterPrototype"),
        .target(name: "AstronomyPolynomialSaturnPrototype"),
        .target(name: "AstronomyPolynomialUranusPrototype"),
        .target(name: "AstronomyPolynomialNeptunePrototype"),
        .target(name: "AstronomyVSOPPrototype"),
        .target(name: "AstronomyNutationPrototype"),
        .target(name: "AstronomyModelPrototypeGenerated"),
        .target(
            name: "AstronomyModelPrototype",
            dependencies: [
                "AstronomyModelPrototypeGenerated",
                "AstronomyPolynomialMercuryPrototype",
                "AstronomyPolynomialVenusPrototype",
                "AstronomyPolynomialEarthPrototype",
                "AstronomyPolynomialMarsPrototype",
                "AstronomyPolynomialJupiterPrototype",
                "AstronomyPolynomialSaturnPrototype",
                "AstronomyPolynomialUranusPrototype",
                "AstronomyPolynomialNeptunePrototype",
                "AstronomyVSOPPrototype",
                "AstronomyNutationPrototype",
            ]
        ),
        .executableTarget(
            name: "AstronomyModelPrototypeRunner", dependencies: ["AstronomyModelPrototype"],
            path: "Tools/Migration/ModelPrototypeRunner"),
        .testTarget(name: "AstronomyModelPrototypeTests", dependencies: ["AstronomyModelPrototype"]),
        .executableTarget(
            name: "AstronomySunPilotRunner", dependencies: ["AstronomyModelPrototype"],
            path: "Tools/Migration/SunPilotRunner"),
        .executableTarget(
            name: "AstronomyRSSMinimalSwift",
            path: "Tools/Migration/SunPilotRSSDiagnostics/MinimalSwiftRunner"),
        .executableTarget(
            name: "AstronomyRSSFoundationOnly",
            path: "Tools/Migration/SunPilotRSSDiagnostics/FoundationOnlyRunner"),
        .executableTarget(
            name: "AstronomyRSSModelLinked", dependencies: ["AstronomyModelPrototype"],
            path: "Tools/Migration/SunPilotRSSDiagnostics/ModelLinkedRunner"),
        .testTarget(
            name: "AstronomySunPilotTests",
            dependencies: ["AstronomyModelPrototype", "CLibAstronomy", "AstronomySunPilotRunner"]),
    ]
)

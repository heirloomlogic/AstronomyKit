//
//  EngineConstellations.swift
//  AstronomyKit
//
//  Native constellation lookup against the Roman 1987 B1875 boundary table.
//

import Foundation

extension Engine {
    /// Mean equator and equinox of B1875, as used by the IAU constellation boundaries.
    enum B1875: Frame {}

    enum Constellations {
        struct Info: Sendable {
            let symbol: String
            let name: String
        }

        struct Boundary: Sendable {
            let infoIndex: Int
            let rightAscensionLower: Double
            let rightAscensionUpper: Double
            let declinationLower: Double
        }

        struct Result: Equatable, Hashable, Sendable {
            let symbol: String
            let name: String
            let rightAscension1875: Double
            let declination1875: Double
        }

        /// The Herget mean-place rotation published with CDS/VizieR catalog VI/42.
        static let b1875Rotation: Engine.Rotation<Engine.EQJ, Engine.B1875> = {
            let radiansPerDegree = 0.17453292519943e-01
            let arcseconds = radiansPerDegree / 3_600
            let centuries = 0.001 * (1_875.0 - 2_000.0)
            let start = 0.001 * (2_000.0 - 1_900.0)
            let a =
                arcseconds * centuries
                * (23_042.53 + start * (139.75 + 0.06 * start)
                    + centuries * (30.23 - 0.27 * start + 18 * centuries))
            let b = arcseconds * centuries * centuries * (79.27 + 0.66 * start + 0.32 * centuries) + a
            let c =
                arcseconds * centuries
                * (20_046.85 - start * (85.33 + 0.37 * start)
                    + centuries * (-42.67 - 0.37 * start - 41.8 * centuries))
            let sinA = sin(a)
            let sinB = sin(b)
            let sinC = sin(c)
            let cosA = cos(a)
            let cosB = cos(b)
            let cosC = cos(c)
            let row0 = (cosA * cosB * cosC - sinA * sinB, -cosA * sinB - sinA * cosB * cosC, -cosB * sinC)
            let row1 = (sinA * cosB + cosA * sinB * cosC, cosA * cosB - sinA * sinB * cosC, -sinB * sinC)
            let row2 = (cosA * sinC, -sinA * sinC, cosC)
            return Engine.Rotation(rot: ((row0.0, row1.0, row2.0), (row0.1, row1.1, row2.1), (row0.2, row1.2, row2.2)))
        }()

        static func find(rightAscension: Double, declination: Double) throws -> Result {
            guard rightAscension.isFinite, declination.isFinite, (-90...90).contains(declination) else {
                throw AstronomyError.invalidParameter
            }
            let normalizedRightAscension = normalizedHours(rightAscension)
            let radiansPerHour = 0.2617993878
            let radiansPerDegree = 0.17453292519943e-01
            let rightAscensionRadians = normalizedRightAscension * radiansPerHour
            let declinationRadians = declination * radiansPerDegree
            let projected = cos(declinationRadians)
            let x = projected * cos(rightAscensionRadians)
            let y = projected * sin(rightAscensionRadians)
            let z = sin(declinationRadians)
            let movedX = b1875Rotation[0, 0] * x + b1875Rotation[1, 0] * y + b1875Rotation[2, 0] * z
            let movedY = b1875Rotation[0, 1] * x + b1875Rotation[1, 1] * y + b1875Rotation[2, 1] * z
            let movedZ = b1875Rotation[0, 2] * x + b1875Rotation[1, 2] * y + b1875Rotation[2, 2] * z
            var resultRightAscension = atan2(movedY, movedX)
            if resultRightAscension < 0 { resultRightAscension += 2 * .pi }
            let resultDeclination =
                min(90, max(-90, asin(min(1, max(-1, movedZ))) / radiansPerDegree))
            return try findB1875(
                rightAscension: resultRightAscension / radiansPerHour,
                declination: resultDeclination
            )
        }

        static func findB1875(rightAscension: Double, declination: Double) throws -> Result {
            guard rightAscension.isFinite, declination.isFinite, (-90...90).contains(declination) else {
                throw AstronomyError.invalidParameter
            }
            let normalizedRightAscension = normalizedHours(rightAscension)
            guard
                let boundary = boundaries.first(where: {
                    $0.declinationLower <= declination
                        && $0.rightAscensionLower <= normalizedRightAscension
                        && normalizedRightAscension < $0.rightAscensionUpper
                })
            else {
                throw AstronomyError.internalError
            }
            let info = infos[boundary.infoIndex]
            return Result(
                symbol: info.symbol,
                name: info.name,
                rightAscension1875: normalizedRightAscension,
                declination1875: declination
            )
        }

        private static func normalizedHours(_ rightAscension: Double) -> Double {
            let remainder = rightAscension.truncatingRemainder(dividingBy: 24)
            guard remainder < 0 else { return remainder }
            let wrapped = remainder + 24
            return wrapped == 24 ? 0 : wrapped
        }
    }
}

//
//  ObserverTests.swift
//  AstronomyKit
//
//  Comprehensive tests for the Observer type.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Observer Tests")
struct ObserverTests {
    // MARK: - Coordinate Validation Tests

    @Suite("Coordinate Validation")
    struct CoordinateValidation {
        static let time = AstroTime(year: 2_025, month: 1, day: 1)

        @Test("NaN latitude throws invalidParameter at calculation time")
        func nanLatitudeThrows() {
            let observer = Observer(latitude: .nan, longitude: 0)
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try observer.vector(at: Self.time)
            }
        }

        @Test("Latitude beyond 90 throws invalidParameter at calculation time")
        func outOfRangeLatitudeThrows() {
            let observer = Observer(latitude: 91, longitude: 0)
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try observer.vector(at: Self.time)
            }
        }

        @Test("Infinite height throws invalidParameter at calculation time")
        func infiniteHeightThrows() {
            let observer = Observer(latitude: 40, longitude: -74, height: .infinity)
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try CelestialBody.moon.equatorial(at: Self.time, from: observer)
            }
        }

        @Test("Valid observer computes normally")
        func validObserverSucceeds() throws {
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)
            _ = try observer.vector(at: Self.time)
        }
    }

    // MARK: - Construction Tests

    @Suite("Construction")
    struct Construction {
        @Test("Create with latitude and longitude")
        func createWithLatLon() {
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)

            #expect(observer.latitude == 40.7128)
            #expect(observer.longitude == -74.0060)
            #expect(observer.height == 0)  // Default height
        }

        @Test("Create with all parameters")
        func createWithAllParams() {
            let observer = Observer(latitude: 27.9881, longitude: 86.9250, height: 8_848.86)

            #expect(observer.latitude == 27.9881)
            #expect(observer.longitude == 86.9250)
            #expect(observer.height == 8_848.86)
        }

        @Test("Equator location")
        func equatorLocation() {
            let observer = Observer(latitude: 0, longitude: 0)

            #expect(observer.latitude == 0)
            #expect(observer.longitude == 0)
        }

        @Test("North pole")
        func northPole() {
            let observer = Observer(latitude: 90, longitude: 0)

            #expect(observer.latitude == 90)
        }

        @Test("South pole")
        func southPole() {
            let observer = Observer(latitude: -90, longitude: 0)

            #expect(observer.latitude == -90)
        }

        @Test("International date line")
        func dateLine() {
            let observerWest = Observer(latitude: 0, longitude: -180)
            let observerEast = Observer(latitude: 0, longitude: 180)

            #expect(observerWest.longitude == -180)
            #expect(observerEast.longitude == 180)
        }
    }

    // MARK: - Common Locations

    @Suite("Common Locations")
    struct CommonLocations {
        @Test("Prime meridian")
        func primeMeridian() {
            let observer = Observer.primeMeridian

            #expect(observer.latitude == 0)
            #expect(observer.longitude == 0)
            #expect(observer.height == 0)
        }

        @Test("Greenwich Observatory")
        func greenwich() {
            let observer = Observer.greenwich

            #expect(observer.latitude > 51 && observer.latitude < 52)
            #expect(observer.longitude < 0 && observer.longitude > -1)
            #expect(observer.height > 0)
        }
    }

    // MARK: - Gravity Tests

    @Suite("Gravity")
    struct GravityTests {
        @Test("Gravity is positive")
        func gravityPositive() {
            let observer = Observer(latitude: 40, longitude: -74)

            #expect(observer.gravity > 0)
        }

        @Test("Gravity higher at poles than equator")
        func gravityLatitudeEffect() {
            let equator = Observer(latitude: 0, longitude: 0)
            let pole = Observer(latitude: 90, longitude: 0)

            #expect(pole.gravity > equator.gravity)
        }

        @Test("Gravity lower at high altitude")
        func gravityAltitudeEffect() {
            let seaLevel = Observer(latitude: 40, longitude: -74, height: 0)
            let mountain = Observer(latitude: 40, longitude: -74, height: 8_000)

            #expect(seaLevel.gravity > mountain.gravity)
        }

        @Test("Gravity is approximately 9.8 m/s²")
        func gravityMagnitude() {
            let observer = Observer(latitude: 45, longitude: 0)

            #expect(observer.gravity > 9.7)
            #expect(observer.gravity < 9.9)
        }

        /// WGS 84 normal gravity on the ellipsoid, Somigliana's closed form
        /// γ = γe (1 + k sin²φ) / √(1 − e² sin²φ), with the constants of NIMA
        /// TR8350.2, 3rd edition (2000), chapter 4.
        static let equatorialGravity = 9.780_325_335_9
        static let polarGravity = 9.832_184_937_8
        static let somiglianaK = 0.001_931_852_652_41
        static let eccentricitySquared = 0.006_694_379_990_14

        /// 1e-9 m/s². The constants are published to 1e-10 m/s², and γp follows
        /// from γe, k and e² to within 6e-11 m/s². Swapping the equator and pole
        /// changes gravity by 0.05 m/s², and using sin φ in place of sin²φ
        /// changes it by 0.01 m/s² at 45°.
        static let somiglianaTolerance = 1e-9

        static func somigliana(latitude: Double) -> Double {
            let s2 = pow(sin(latitude * .pi / 180), 2)
            return equatorialGravity * (1 + somiglianaK * s2) / (1 - eccentricitySquared * s2).squareRoot()
        }

        @Test(
            "Sea-level gravity at the equator and poles is the published WGS 84 value",
            arguments: [(0.0, equatorialGravity), (90.0, polarGravity), (-90.0, polarGravity)]
        )
        func gravityAtEquatorAndPoles(latitude: Double, expected: Double) {
            let gravity = Observer(latitude: latitude, longitude: 0).gravity

            #expect(abs(gravity - expected) < Self.somiglianaTolerance, "\(gravity) m/s², expected \(expected)")
        }

        @Test("Sea-level gravity between them follows Somigliana's formula", arguments: [30.0, 45.0, -60.0])
        func gravityFollowsSomigliana(latitude: Double) {
            let gravity = Observer(latitude: latitude, longitude: 0).gravity
            let expected = Self.somigliana(latitude: latitude)

            #expect(abs(gravity - expected) < Self.somiglianaTolerance, "\(gravity) m/s², expected \(expected)")
        }

        /// WGS 84 defining parameters, NIMA TR8350.2, 3rd edition (2000),
        /// Table 3.1: semi-major axis, reciprocal flattening, angular velocity
        /// and geocentric gravitational constant.
        static let semiMajorAxis = 6_378_137.0
        static let flattening = 1 / 298.257_223_563
        static let angularVelocity = 7_292_115e-11
        static let gravitationalConstant = 3_986_004.418e8

        /// m = ω²a²b/GM, which TR8350.2 lists among its derived constants as
        /// 0.00344978650684.
        static let gravityRatio =
            angularVelocity * angularVelocity * semiMajorAxis * semiMajorAxis * (semiMajorAxis * (1 - flattening))
            / gravitationalConstant

        /// Normal gravity at height h above the ellipsoid, TR8350.2 eq. 4-3:
        /// γh = γ [1 − (2/a)(1 + f + m − 2f sin²φ) h + (3/a²) h²].
        static func normalGravity(latitude: Double, height: Double) -> Double {
            let s2 = pow(sin(latitude * .pi / 180), 2)
            let a = semiMajorAxis
            let f = flattening
            let linear = 2 / a * (1 + f + gravityRatio - 2 * f * s2) * height
            let quadratic = 3 / (a * a) * height * height
            return somigliana(latitude: latitude) * (1 - linear + quadratic)
        }

        /// 5e-12 m/s² per metre of height, on top of the sea-level tolerance.
        /// The engine stores the eq. 4-3 coefficients rounded to six digits;
        /// the linear one, 3.15704e-7 against 3.157042871e-7, leaves
        /// 2.8e-12 m/s² per metre (2.8e-7 m/s² at 100 km), and the other two
        /// add under 4e-9 m/s² there. A change in the sixth digit of the linear
        /// coefficient moves gravity at 100 km by 9.8e-7 m/s².
        static let heightToleranceRate = 5e-12

        @Test(
            "Gravity above sea level follows the WGS 84 free-air expansion",
            arguments: [(0.0, 10_000.0), (45.0, 50_000.0), (90.0, 100_000.0), (-30.0, 100_000.0)]
        )
        func gravityAboveSeaLevel(latitude: Double, height: Double) {
            let gravity = Observer(latitude: latitude, longitude: 0, height: height).gravity
            let expected = Self.normalGravity(latitude: latitude, height: height)
            let tolerance = Self.somiglianaTolerance + Self.heightToleranceRate * height

            #expect(abs(gravity - expected) < tolerance, "\(gravity) m/s², expected \(expected)")
        }
    }

    // MARK: - Protocol Conformances

    @Suite("Protocol Conformances")
    struct ProtocolConformances {
        @Test("Equatable - equal observers")
        func equatableEqual() {
            let obs1 = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)
            let obs2 = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)

            #expect(obs1 == obs2)
        }

        @Test("Equatable - different latitude")
        func equatableDifferentLat() {
            let obs1 = Observer(latitude: 40.7128, longitude: -74.0060)
            let obs2 = Observer(latitude: 41.0, longitude: -74.0060)

            #expect(obs1 != obs2)
        }

        @Test("Equatable - different longitude")
        func equatableDifferentLon() {
            let obs1 = Observer(latitude: 40.7128, longitude: -74.0060)
            let obs2 = Observer(latitude: 40.7128, longitude: -73.0)

            #expect(obs1 != obs2)
        }

        @Test("Equatable - different height")
        func equatableDifferentHeight() {
            let obs1 = Observer(latitude: 40.7128, longitude: -74.0060, height: 0)
            let obs2 = Observer(latitude: 40.7128, longitude: -74.0060, height: 100)

            #expect(obs1 != obs2)
        }

        @Test("Hashable - equal observers have equal hashes")
        func hashableEqual() {
            let obs1 = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)
            let obs2 = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)

            #expect(obs1.hashValue == obs2.hashValue)
        }

        @Test("Hashable - can be used in Set")
        func hashableInSet() {
            let nyc = Observer(latitude: 40.7128, longitude: -74.0060)
            let london = Observer(latitude: 51.5074, longitude: -0.1278)
            let nycDupe = Observer(latitude: 40.7128, longitude: -74.0060)

            let set: Set<Observer> = [nyc, london, nycDupe]

            #expect(set.count == 2)
        }

        @Test("CustomStringConvertible - contains coordinates")
        func description() {
            let observer = Observer(latitude: 40.7128, longitude: -74.0060)
            let desc = observer.description

            #expect(desc.contains("N"))
            #expect(desc.contains("W"))
        }

        @Test("CustomStringConvertible - includes height when non-zero")
        func descriptionWithHeight() {
            let observer = Observer(latitude: 40.7128, longitude: -74.0060, height: 100)
            let desc = observer.description

            #expect(desc.contains("m"))
        }

        @Test("CustomStringConvertible - southern/eastern coordinates")
        func descriptionSouthEast() {
            let observer = Observer(latitude: -33.8688, longitude: 151.2093)  // Sydney
            let desc = observer.description

            #expect(desc.contains("S"))
            #expect(desc.contains("E"))
        }

        @Test(
            "CustomStringConvertible - non-finite and huge heights don't crash",
            arguments: [Double.infinity, -.infinity, .nan, 1e300]
        )
        func descriptionExtremeHeight(height: Double) {
            let observer = Observer(latitude: 0, longitude: 0, height: height)

            #expect(!observer.description.isEmpty)
        }
    }

    // MARK: - Codable Tests

    @Suite("Codable")
    struct CodableTests {
        @Test("Encode and decode round-trip")
        func encodeDecodeRoundTrip() throws {
            let original = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)

            let encoder = JSONEncoder()
            let data = try encoder.encode(original)

            let decoder = JSONDecoder()
            let decoded = try decoder.decode(Observer.self, from: data)

            #expect(original == decoded)
        }

        @Test("Encodes with expected keys")
        func encodesWithKeys() throws {
            let observer = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)

            let encoder = JSONEncoder()
            let data = try encoder.encode(observer)
            let json = String(data: data, encoding: .utf8)!

            #expect(json.contains("latitude"))
            #expect(json.contains("longitude"))
            #expect(json.contains("height"))
        }

        @Test("Decode from JSON object")
        func decodeFromJSON() throws {
            let json = """
                {"latitude": 51.5074, "longitude": -0.1278, "height": 11}
                """
            let data = json.data(using: .utf8)!

            let decoder = JSONDecoder()
            let observer = try decoder.decode(Observer.self, from: data)

            #expect(observer.latitude == 51.5074)
            #expect(observer.longitude == -0.1278)
            #expect(observer.height == 11)
        }
    }

    // MARK: - Edge Cases

    @Suite("Edge Cases")
    struct EdgeCases {
        @Test("Very high altitude")
        func veryHighAltitude() {
            let observer = Observer(latitude: 0, longitude: 0, height: 35_786_000)  // Geostationary orbit

            #expect(observer.height == 35_786_000)
            #expect(observer.gravity >= 0)  // Should still compute (though may be very small)
        }

        @Test("Negative height (below sea level)")
        func belowSeaLevel() {
            let deadsea = Observer(latitude: 31.5, longitude: 35.5, height: -430)

            #expect(deadsea.height == -430)
            #expect(deadsea.gravity > 9.7)  // Slightly higher than at sea level
        }

        @Test("Precise coordinate values maintained")
        func precisionMaintained() {
            let precise = Observer(
                latitude: 40.71280000001,
                longitude: -74.00600000002,
                height: 10.123456789
            )

            #expect(precise.latitude == 40.71280000001)
            #expect(precise.longitude == -74.00600000002)
            #expect(precise.height == 10.123456789)
        }
    }
}

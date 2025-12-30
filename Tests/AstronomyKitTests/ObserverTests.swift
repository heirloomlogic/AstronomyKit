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
            let observer = Observer(latitude: 27.9881, longitude: 86.9250, height: 8848.86)

            #expect(observer.latitude == 27.9881)
            #expect(observer.longitude == 86.9250)
            #expect(observer.height == 8848.86)
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
            let mountain = Observer(latitude: 40, longitude: -74, height: 8000)

            #expect(seaLevel.gravity > mountain.gravity)
        }

        @Test("Gravity is approximately 9.8 m/s²")
        func gravityMagnitude() {
            let observer = Observer(latitude: 45, longitude: 0)

            #expect(observer.gravity > 9.7)
            #expect(observer.gravity < 9.9)
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

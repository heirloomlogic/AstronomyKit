//
//  AtmosphereTests.swift
//  AstronomyKit
//
//  Tests for Atmosphere functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Atmosphere Tests")
struct AtmosphereTests {

    @Test("Sea level atmosphere")
    func seaLevelAtmosphere() throws {
        let atm = try Atmosphere.at(elevation: 0)

        // Sea level pressure ~1013.25 mbar
        #expect(atm.pressure > 1_010 && atm.pressure < 1_020)

        // Sea level temp ~15°C in ISA
        #expect(atm.temperature > 14 && atm.temperature < 16)

        // Sea level density = 1.0 (reference)
        #expect(abs(atm.density - 1.0) < 0.01)
    }

    @Test("Higher elevation has lower pressure")
    func higherElevationLowerPressure() throws {
        let seaLevel = try Atmosphere.at(elevation: 0)
        let mountain = try Atmosphere.at(elevation: 3_000)

        #expect(mountain.pressure < seaLevel.pressure)
        #expect(mountain.density < seaLevel.density)
    }

    @Test("Mount Everest summit")
    func mountEverest() throws {
        let atm = try Atmosphere.at(elevation: 8_848.86)

        // Pressure should be about 1/3 of sea level
        #expect(atm.pressure > 300 && atm.pressure < 350)

        // Temperature should be very cold
        #expect(atm.temperature < -30)
    }

    @Test("Observer atmosphere property")
    func observerAtmosphere() throws {
        let observer = Observer(
            latitude: 27.9881,
            longitude: 86.9250,
            height: 5_000  // 5km elevation
        )

        let atm = try observer.atmosphere

        #expect(atm.pressure < 600)  // Much lower than sea level
    }

    @Test("Atmosphere is Equatable")
    func equatable() throws {
        let atm1 = try Atmosphere.at(elevation: 1_000)
        let atm2 = try Atmosphere.at(elevation: 1_000)

        #expect(atm1 == atm2)
    }

    @Test("CustomStringConvertible")
    func description() throws {
        let atm = try Atmosphere.at(elevation: 0)
        let desc = atm.description

        #expect(desc.contains("mbar"))
        #expect(desc.contains("°C"))
    }
}

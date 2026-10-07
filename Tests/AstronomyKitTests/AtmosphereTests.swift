//
//  AtmosphereTests.swift
//  AstronomyKit
//
//  Tests for Atmosphere functionality.
//

import Foundation
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

    // MARK: - Standard Atmosphere Values

    /// The 1976 U.S. Standard Atmosphere, which agrees with the ISO 2533
    /// (ICAO) standard atmosphere below 32 km to within 3.3e-6 in pressure:
    /// 101,325 Pa and 288.15 K at sea level, −6.5 K/km to 11 km, 216.65 K to
    /// 20 km, then +1 K/km to 32 km, with geopotential heights.
    ///
    /// 1e-9: pressure and temperature here are exact in the standard, so the
    /// only error is converting Pa to mbar and K to °C (about 1e-13). A Kelvin
    /// offset wrong by 0.1 K shows at every height, and a 1 % lapse-rate error
    /// moves the 5 km temperature by 0.33 K.
    static let standardTolerance = 1e-9

    @Test("Sea level is the standard atmosphere's base")
    func seaLevelBase() throws {
        let atm = try Atmosphere.at(elevation: 0)

        #expect(abs(atm.pressure - 1_013.25) < Self.standardTolerance, "\(atm.pressure) mbar")
        #expect(abs(atm.temperature - 15) < Self.standardTolerance, "\(atm.temperature)°C")
        #expect(abs(atm.density - 1) < Self.standardTolerance, "density \(atm.density)")
    }

    @Test(
        "Temperature follows the standard lapse rates",
        arguments: [
            (5_000.0, 255.65), (11_000, 216.65), (15_000, 216.65), (20_000, 216.65), (26_000, 222.65),
            (32_000, 228.65),
        ]
    )
    func standardTemperature(geopotentialHeight: Double, kelvin: Double) throws {
        let atm = try Atmosphere.at(elevation: geopotentialHeight)
        let expected = kelvin - 273.15

        #expect(abs(atm.temperature - expected) < Self.standardTolerance, "\(atm.temperature)°C, expected \(expected)")
    }

    /// Pressure and density of the 1976 U.S. Standard Atmosphere
    /// (NOAA-S/T 76-1562), computed from its defining constants rather than
    /// from rounded tables: g0 = 9.80665 m/s², M0 = 28.9644 kg/kmol,
    /// R* = 8,314.32 J/(kmol·K), sea level 101,325 Pa and 288.15 K, and lapse
    /// rates of −6.5, 0 and +1 K/km in the layers that start at 0, 11 and
    /// 20 km geopotential. Each layer starts from the pressure at the top of
    /// the one below, so the 11 km and 20 km base pressures (22,632.064 Pa and
    /// 5,474.889 Pa) follow from the constants. The troposphere exponent is
    /// g0·M0/(R*·L) = 5.2558761.
    enum Standard1976 {
        static let gravity = 9.806_65
        static let molarMass = 28.964_4
        static let gasConstant = 8_314.32
        static let seaLevelPressure = 101_325.0
        static let seaLevelTemperature = 288.15
        static let troposphereLapseRate = 0.006_5
        static let upperLapseRate = 0.001
        static let tropopause = 11_000.0
        static let stratopause = 20_000.0

        static let tropopauseTemperature = seaLevelTemperature - troposphereLapseRate * tropopause
        static let troposphereExponent = gravity * molarMass / (gasConstant * troposphereLapseRate)
        static let tropopausePressure =
            seaLevelPressure * pow(tropopauseTemperature / seaLevelTemperature, troposphereExponent)
        static let isothermalRate = gravity * molarMass / (gasConstant * tropopauseTemperature)
        static let stratopausePressure = tropopausePressure * exp(-isothermalRate * (stratopause - tropopause))

        static func temperature(at height: Double) -> Double {
            if height <= tropopause { return seaLevelTemperature - troposphereLapseRate * height }
            if height <= stratopause { return tropopauseTemperature }
            return tropopauseTemperature + upperLapseRate * (height - stratopause)
        }

        static func pressure(at height: Double) -> Double {
            let t = temperature(at: height)
            if height <= tropopause { return seaLevelPressure * pow(t / seaLevelTemperature, troposphereExponent) }
            if height <= stratopause { return tropopausePressure * exp(-isothermalRate * (height - tropopause)) }
            let exponent = gravity * molarMass / (gasConstant * upperLapseRate)
            return stratopausePressure * pow(tropopauseTemperature / t, exponent)
        }

        /// Density relative to sea level, ρ/ρ0 = (P/P0)(T0/T), from the
        /// standard's equation of state ρ = P·M0/(R*·T).
        static func relativeDensity(at height: Double) -> Double {
            pressure(at: height) / seaLevelPressure * seaLevelTemperature / temperature(at: height)
        }
    }

    static let pressureHeights = [1_000.0, 5_000, 8_848.86, 11_000, 15_000, 20_000, 26_000, 32_000]

    /// 1e-7 relative. The exponent is usually published to seven figures as
    /// 5.255876, which is 1.1e-7 below the closed form and moves pressure by
    /// at most 3.2e-8 (at 11 km), so either value passes. The C engine's
    /// 5.25577 is 3.0e-5 off at 11 km, its rounded stratosphere base
    /// pressures 2e-6 to 3.3e-6, and the ICAO exponent 5.2558798 1.0e-6.
    static let closedFormTolerance = 1e-7

    /// The native engine computes every layer from the defining constants
    /// (#153).
    @Test("Pressure and density are the 1976 standard's closed form", arguments: pressureHeights)
    func pressureAndDensityAreStandard(geopotentialHeight: Double) throws {
        let atm = try Atmosphere.at(elevation: geopotentialHeight)
        let pressure = atm.pressure / (Standard1976.pressure(at: geopotentialHeight) / 100) - 1
        let density = atm.density / Standard1976.relativeDensity(at: geopotentialHeight) - 1

        #expect(abs(pressure) < Self.closedFormTolerance, "\(atm.pressure) mbar, relative error \(pressure)")
        #expect(abs(density) < Self.closedFormTolerance, "density \(atm.density), relative error \(density)")
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

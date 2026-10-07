//
//  EngineAtmosphere.swift
//  AstronomyKit
//
//  The 1976 U.S. Standard Atmosphere below 32 km.
//

import Foundation

extension Engine {
    /// Pressure in pascals, temperature in kelvins and density relative to
    /// sea level at one elevation, from the 1976 U.S. Standard Atmosphere
    /// (NOAA-S/T 76-1562).
    struct Atmosphere: Equatable, Sendable {
        var pressure: Double
        var temperature: Double
        var density: Double
    }
}

extension Engine.Atmosphere {
    // The standard's defining constants.
    private static let gravity = 9.806_65  // g0, m/s²
    private static let molarMass = 28.964_4  // M0, kg/kmol
    private static let gasConstant = 8_314.32  // R*, J/(kmol·K)
    private static let seaLevelPressure = 101_325.0  // Pa
    private static let seaLevelTemperature = 288.15  // K
    private static let troposphereLapseRate = 0.006_5  // K/m, to 11 km
    private static let upperLapseRate = 0.001  // K/m, from 20 km
    private static let tropopause = 11_000.0  // m
    private static let stratopause = 20_000.0  // m

    /// g0·M0/R*, in K/m: the hydrostatic constant of every layer.
    private static let hydrostatic = gravity * molarMass / gasConstant
    private static let tropopauseTemperature = seaLevelTemperature - troposphereLapseRate * tropopause
    private static let tropopausePressure =
        seaLevelPressure * pow(tropopauseTemperature / seaLevelTemperature, hydrostatic / troposphereLapseRate)
    private static let stratopausePressure =
        tropopausePressure * exp(-hydrostatic / tropopauseTemperature * (stratopause - tropopause))

    /// The atmosphere at `elevation` metres of geopotential height
    /// (`Astronomy_Atmosphere`).
    ///
    /// The layers are the standard's first three: −6.5 K/km to 11 km,
    /// isothermal to 20 km, then +1 K/km. Each layer starts from the pressure
    /// at the top of the one below, computed from the defining constants, so
    /// the troposphere exponent is g0·M0/(R*·L) = 5.2558761 (#153). As in the
    /// C engine, the third layer continues to 100 km, though the standard
    /// changes layer at 32 km (#175).
    ///
    /// - Throws: `AstronomyError.invalidParameter` for an elevation that is
    ///   not finite or is outside −500 to 100,000 m.
    init(elevation: Double) throws {
        guard (-500...100_000).contains(elevation) else {
            throw AstronomyError.invalidParameter
        }
        let t0 = Self.seaLevelTemperature
        let t1 = Self.tropopauseTemperature
        if elevation <= Self.tropopause {
            temperature = t0 - Self.troposphereLapseRate * elevation
            pressure = Self.seaLevelPressure * pow(temperature / t0, Self.hydrostatic / Self.troposphereLapseRate)
        } else if elevation <= Self.stratopause {
            temperature = t1
            pressure = Self.tropopausePressure * exp(-Self.hydrostatic / t1 * (elevation - Self.tropopause))
        } else {
            temperature = t1 + Self.upperLapseRate * (elevation - Self.stratopause)
            pressure = Self.stratopausePressure * pow(t1 / temperature, Self.hydrostatic / Self.upperLapseRate)
        }
        // The equation of state ρ = P·M0/(R*·T), relative to sea level.
        density = (pressure / temperature) / (Self.seaLevelPressure / t0)
    }
}

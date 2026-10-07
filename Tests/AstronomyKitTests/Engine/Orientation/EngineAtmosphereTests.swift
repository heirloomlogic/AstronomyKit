//
//  EngineAtmosphereTests.swift
//  AstronomyKit
//
//  The 1976 U.S. Standard Atmosphere against its published values.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Atmosphere")
struct EngineAtmosphereTests {
    typealias Standard = AtmosphereTests.Standard1976

    /// The layer base values of the 1976 U.S. Standard Atmosphere
    /// (NOAA-S/T 76-1562): geopotential height in metres, temperature in
    /// kelvins and pressure in pascals as the standard prints them, to seven
    /// significant figures.
    static let layerBases: [(height: Double, temperature: Double, pressure: Double)] = [
        (0, 288.15, 101_325.0),
        (11_000, 216.65, 22_632.06),
        (20_000, 216.65, 5_474.889),
        (32_000, 228.65, 868.018_7),
    ]

    /// 3e-7 relative: half a unit in the seventh printed figure of 22,632.06.
    @Test("Layer bases match the standard's printed table", arguments: layerBases.indices)
    func layerBase(index: Int) throws {
        let base = Self.layerBases[index]
        let atmosphere = try Engine.Atmosphere(elevation: base.height)
        #expect(abs(atmosphere.temperature - base.temperature) <= 1e-12)
        #expect(abs(atmosphere.pressure / base.pressure - 1) <= 3e-7)
    }

    /// 1e-12 relative: the test computes the same closed form from the
    /// defining constants, independently of the engine, in
    /// `AtmosphereTests.Standard1976`.
    @Test(
        "Pressure, temperature and density follow the closed form",
        arguments: [
            -500.0, 0, 1_000, 8_848.86, 10_999.999, 11_000, 11_000.001, 15_000, 19_999.999, 20_000, 20_000.001, 26_000,
            32_000,
        ]
    )
    func closedForm(height: Double) throws {
        let atmosphere = try Engine.Atmosphere(elevation: height)
        #expect(abs(atmosphere.temperature / Standard.temperature(at: height) - 1) <= 1e-12)
        #expect(abs(atmosphere.pressure / Standard.pressure(at: height) - 1) <= 1e-12)
        #expect(abs(atmosphere.density / Standard.relativeDensity(at: height) - 1) <= 1e-12)
    }

    @Test("Pressure is continuous at the layer boundaries", arguments: [11_000.0, 20_000])
    func continuity(boundary: Double) throws {
        let below = try Engine.Atmosphere(elevation: boundary)
        let above = try Engine.Atmosphere(elevation: boundary.nextUp)
        #expect(abs(above.pressure / below.pressure - 1) <= 1e-12)
        #expect(abs(above.temperature - below.temperature) <= 1e-9)
    }

    @Test("Sea level has density 1")
    func seaLevel() throws {
        let expected = Engine.Atmosphere(pressure: 101_325, temperature: 288.15, density: 1)
        #expect(try Engine.Atmosphere(elevation: 0) == expected)
    }

    @Test("The range ends are accepted", arguments: [-500.0, 100_000])
    func rangeEnds(height: Double) throws {
        let atmosphere = try Engine.Atmosphere(elevation: height)
        #expect(atmosphere.pressure > 0 && atmosphere.density > 0)
    }

    @Test(
        "Elevations outside -500 to 100,000 m or not finite are rejected",
        arguments: [(-500.0).nextDown, 100_000.0.nextUp, .nan, .infinity, -.infinity]
    )
    func outOfRange(height: Double) {
        #expect(throws: AstronomyError.invalidParameter) { try Engine.Atmosphere(elevation: height) }
    }
}

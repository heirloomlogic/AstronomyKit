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

    /// r0, the earth radius of the standard's geopotential (table 2).
    static let earthRadius = 6_356_766.0

    /// The geopotential height in m′ of geometric height `z` metres (eq 18).
    static func geopotential(_ z: Double) -> Double {
        earthRadius * z / (earthRadius + z)
    }

    /// The geometric height in metres of geopotential height `h` m′ (eq 19).
    static func geometric(_ h: Double) -> Double {
        earthRadius * h / (earthRadius - h)
    }

    /// Half a unit in the last of `figures` significant figures of `value`,
    /// relative to `value`: the most a correct result can differ from a
    /// printed one.
    static func halfUnit(_ value: Double, figures: Int) -> Double {
        let unit = pow(10, (log10(abs(value))).rounded(.down) - Double(figures - 1))
        return unit / 2 / abs(value)
    }

    /// The standard's printed tables stray from its own equations by more
    /// than their rounding. Above 32 km, table I's pressures sit below the
    /// closed form by up to 5.7e-5 (at 47 km it prints 1.1090 mb for
    /// 1.109063). From 86 to 102 km its pressures and table VIII's number
    /// densities scatter about this model, with both signs, by up to 1.8e-5
    /// more than their rounding. Comparisons with those tables allow this on
    /// top of half a unit in the last printed figure.
    static let tableSlack = 6e-5

    // MARK: - Below 86 km

    /// Layer bases of the 1976 U.S. Standard Atmosphere (NOAA-S/T 76-1562):
    /// geopotential height in metres, temperature in kelvins and pressure in
    /// pascals as the standard prints them, with the number of significant
    /// figures printed. The bases from 47 km come from table I, which prints
    /// pressure to five figures in millibars and carries `tableSlack`.
    static let layerBases: [(height: Double, temperature: Double, pressure: Double, figures: Int)] = [
        (0, 288.15, 101_325.0, 7),
        (11_000, 216.65, 22_632.06, 7),
        (20_000, 216.65, 5_474.889, 7),
        (32_000, 228.65, 868.018_7, 7),
        (47_000, 270.65, 110.90, 5),
        (51_000, 270.65, 66.938, 5),
        (71_000, 214.65, 3.956_4, 5),
    ]

    @Test("Layer bases match the standard's printed table", arguments: layerBases.indices)
    func layerBase(index: Int) throws {
        let base = Self.layerBases[index]
        let atmosphere = try Engine.Atmosphere(elevation: base.height)
        #expect(abs(atmosphere.temperature - base.temperature) <= 1e-12)
        #expect(
            abs(atmosphere.pressure / base.pressure - 1)
                <= Self.halfUnit(base.pressure, figures: base.figures) + (base.figures == 5 ? Self.tableSlack : 0)
        )
    }

    /// 1e-12 relative: the test computes the same closed form from the
    /// defining constants, independently of the engine, in
    /// `AtmosphereTests.Standard1976`. Up to 79,005.7 m geopotential (80 km
    /// geometric) the kinetic temperature is the molecular-scale one.
    @Test(
        "Pressure, temperature and density follow the closed form",
        arguments: [
            -500.0, 0, 1_000, 8_848.86, 10_999.999, 11_000, 11_000.001, 15_000, 19_999.999, 20_000, 20_000.001, 26_000,
            32_000, 40_000, 47_000, 49_000, 51_000, 60_000, 71_000, 75_000, 79_000,
        ]
    )
    func closedForm(height: Double) throws {
        let atmosphere = try Engine.Atmosphere(elevation: height)
        #expect(abs(atmosphere.temperature / Standard.temperature(at: height) - 1) <= 1e-12)
        #expect(abs(atmosphere.pressure / Standard.pressure(at: height) - 1) <= 1e-12)
        #expect(abs(atmosphere.density / Standard.relativeDensity(at: height) - 1) <= 1e-12)
    }

    /// Table 8: M/M0 at every 500 m of geometric height from 80 to 86 km.
    /// The kinetic temperature is the molecular-scale temperature times this
    /// ratio (eq 22); pressure and density do not depend on it.
    static let molecularWeightRatios: [(z: Double, ratio: Double)] = [
        (80_000, 1.000000), (81_000, 0.999989), (83_000, 0.999870), (84_500, 0.999741), (85_500, 0.999641),
        (85_750, (0.999641 + 0.999579) / 2),
    ]

    @Test("Kinetic temperature applies table 8 from 80 to 86 km", arguments: molecularWeightRatios.indices)
    func molecularWeightRatio(index: Int) throws {
        let row = Self.molecularWeightRatios[index]
        let height = Self.geopotential(row.z)
        let atmosphere = try Engine.Atmosphere(elevation: height)
        #expect(abs(atmosphere.temperature - Standard.temperature(at: height) * row.ratio) <= 1e-9)
        #expect(abs(atmosphere.pressure / Standard.pressure(at: height) - 1) <= 1e-12)
        #expect(abs(atmosphere.density / Standard.relativeDensity(at: height) - 1) <= 1e-12)
    }

    @Test(
        "Pressure is continuous at the layer boundaries",
        arguments: [11_000.0, 20_000, 32_000, 47_000, 51_000, 71_000]
    )
    func continuity(boundary: Double) throws {
        let below = try Engine.Atmosphere(elevation: boundary)
        let above = try Engine.Atmosphere(elevation: boundary.nextUp)
        #expect(abs(above.pressure / below.pressure - 1) <= 1e-12)
        #expect(abs(above.temperature - below.temperature) <= 1e-9)
    }

    // MARK: - From 86 km

    /// Table I of the standard by geometric height: kinetic temperature in
    /// kelvins to two decimals, pressure in pascals to five significant
    /// figures and density relative to sea level to four. The comparison
    /// allows `tableSlack` beyond the rounding.
    static let geometricTable: [(z: Double, temperature: Double, pressure: Double, density: Double)] = [
        (86_000, 186.87, 3.733_8e-1, 5.680e-6),
        (88_000, 186.87, 2.617_3e-1, 3.980e-6),
        (90_000, 186.87, 1.835_9e-1, 2.789e-6),
        (91_000, 186.87, 1.538_1e-1, 2.335e-6),
        (92_500, 187.08, 1.179_8e-1, 1.786e-6),
        (93_500, 187.47, 9.889_6e-2, 1.492e-6),
        (95_000, 188.42, 7.596_6e-2, 1.137e-6),
        (97_000, 190.40, 5.357_1e-2, 7.906e-7),
        (98_000, 191.72, 4.505_7e-2, 6.588e-7),
        (99_500, 194.15, 3.484_6e-2, 5.011e-7),
        (100_000, 195.08, 3.201_1e-2, 4.575e-7),
        (101_000, 197.16, 2.719_2e-2, 3.833e-7),
    ]

    @Test("Values from 86 km match table I", arguments: geometricTable.indices)
    func geometricTableRow(index: Int) throws {
        let row = Self.geometricTable[index]
        let atmosphere = try Engine.Atmosphere(elevation: Self.geopotential(row.z))
        #expect(abs(atmosphere.temperature - row.temperature) <= 0.005, "\(atmosphere.temperature) K")
        let pressure = atmosphere.pressure / row.pressure - 1
        let density = atmosphere.density / row.density - 1
        #expect(abs(pressure) <= Self.halfUnit(row.pressure, figures: 5) + Self.tableSlack, "error \(pressure)")
        #expect(abs(density) <= Self.halfUnit(row.density, figures: 4) + Self.tableSlack, "error \(density)")
    }

    /// Table VIII: number densities in m⁻³ of N2, O, O2, Ar and He, to four
    /// significant figures. The comparison allows `tableSlack` beyond the
    /// rounding.
    static let compositionTable: [(z: Double, densities: [Double])] = [
        (86_000, [1.130e20, 8.600e16, 3.031e19, 1.351e18, 7.582e14]),
        (90_000, [5.547e19, 2.443e17, 1.479e19, 6.574e17, 3.976e14]),
        (95_000, [2.268e19, 4.365e17, 5.830e18, 2.583e17, 1.973e14]),
        (97_000, [1.581e19, 4.500e17, 3.943e18, 1.746e17, 1.553e14]),
        (100_000, [9.210e18, 4.298e17, 2.151e18, 9.501e16, 1.133e14]),
        (101_000, [7.740e18, 4.168e17, 1.756e18, 7.735e16, 1.034e14]),
        (102_000, [6.508e18, 4.007e17, 1.430e18, 6.279e16, 9.497e13]),
    ]

    @Test("Number densities match table VIII", arguments: compositionTable.indices)
    func composition(index: Int) {
        let row = Self.compositionTable[index]
        let densities = Engine.Atmosphere.numberDensities(geometricHeight: row.z)
        for (lane, printed) in row.densities.enumerated() {
            let density = densities[lane]
            let error = density / printed - 1
            #expect(abs(error) <= Self.halfUnit(printed, figures: 4) + Self.tableSlack, "\(density), table \(printed)")
        }
    }

    /// The step error peaks just above 91 km, where the ellipse begins, at
    /// about 9e-11.
    @Test(
        "Halving the integration step leaves the densities within 1e-10",
        arguments: [91_500.0, 93_000, 101_598.27]
    )
    func integrationStep(z: Double) {
        let standard = Engine.Atmosphere.numberDensities(geometricHeight: z)
        let finer = Engine.Atmosphere.numberDensities(geometricHeight: z, step: 50)
        for lane in 0..<5 {
            #expect(abs(standard[lane] / finer[lane] - 1) <= 1e-10)
        }
    }

    /// The standard takes 86 km geometric height to be 84,852 m
    /// geopotential, which eq 18 puts at 84,852.046 m. Table 9's number
    /// densities reproduce the pressure and density of the layers below at
    /// 84,852 m to about 1.2e-7, so across the 4.6 cm between the two the
    /// pressure and density step by about 8.5e-6, under table I's rounding
    /// there (1.3e-5). Kinetic temperature meets 186.8673 K to within 1e-4 K.
    @Test("The 86 km boundary is continuous to the standard's precision")
    func geometricBoundary() throws {
        let boundary = Self.geopotential(86_000)
        let below = try Engine.Atmosphere(elevation: boundary - 1e-6)
        let above = try Engine.Atmosphere(elevation: boundary + 1e-6)
        #expect(abs(above.pressure / below.pressure - 1) <= 1e-5)
        #expect(abs(above.density / below.density - 1) <= 1e-5)
        #expect(abs(above.temperature - below.temperature) <= 2e-4)
        #expect(above.temperature == 186.867_3)

        let layers = try Engine.Atmosphere(elevation: 84_852)
        #expect(abs(above.pressure / layers.pressure - 1) <= 3e-7)
        #expect(abs(above.density / layers.density - 1) <= 3e-7)
    }

    /// The temperature profile, the eddy diffusion, the atomic-oxygen flux
    /// and the molecular weights change form at these geometric heights;
    /// the integration carries through each of them.
    @Test("Values are continuous where the upper model changes form", arguments: [91_000.0, 95_000, 97_000, 100_000])
    func upperContinuity(z: Double) throws {
        let height = Self.geopotential(z)
        let below = try Engine.Atmosphere(elevation: height - 1e-6)
        let above = try Engine.Atmosphere(elevation: height + 1e-6)
        #expect(abs(above.pressure / below.pressure - 1) <= 1e-9)
        #expect(abs(above.density / below.density - 1) <= 1e-9)
        #expect(abs(above.temperature - below.temperature) <= 1e-8)
    }

    /// 100 km geopotential is 101,598.27 m geometric (eq 19), between table
    /// I's rows at 101 and 102 km. Its temperature is eq 27's ellipse there.
    /// Its pressure and density are compared with the rows at 100, 101 and
    /// 102 km interpolated quadratically in their logarithm. The
    /// interpolation itself is good to about 1.6e-5, and the rows are rounded
    /// to five figures in pressure (2e-5) and four in density (1.6e-4).
    @Test("The 100 km endpoint follows the ellipse and the table")
    func endpoint() throws {
        let atmosphere = try Engine.Atmosphere(elevation: 100_000)
        let z = Self.geometric(100_000)
        let x = (z / 1_000 - 91) / -19.942_9
        let ellipse = 263.190_5 - 76.323_2 * (1 - x * x).squareRoot()
        #expect(abs(atmosphere.temperature - ellipse) <= 1e-9)

        // Lagrange interpolation on nodes at −1, 0 and +1 km from 101 km.
        let t = (z - 101_000) / 1_000
        func interpolate(_ rows: [Double]) -> Double {
            let logs = rows.map { log($0) }
            return exp(logs[0] * t * (t - 1) / 2 + logs[1] * (1 - t * t) + logs[2] * t * (t + 1) / 2)
        }
        let pressure = interpolate([3.201_1e-2, 2.719_2e-2, 2.314_4e-2])
        let density = interpolate([4.575e-7, 3.833e-7, 3.212e-7])
        #expect(abs(atmosphere.pressure / pressure - 1) <= 5e-5, "\(atmosphere.pressure) Pa")
        #expect(abs(atmosphere.density / density - 1) <= 2e-4, "density \(atmosphere.density)")
    }

    // MARK: - Range

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

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native DE441 Moon")
struct EngineMoonDE441Tests {
    typealias Table = Engine.MoonDE441

    @Test("The shared-endpoint table covers the accepted range and rejects invalid inputs")
    func domain() throws {
        #expect(Table.data.count == 35_064_072)
        #expect(Table.recordCount == 730_501)
        for tt in [-Engine.acceptedTTDays, Engine.acceptedTTDays] {
            #expect(Table.state(tt: tt) != nil)
        }
        for tdb in [Table.start.nextDown, Table.start + Double(Table.recordCount) * 4, .nan, .infinity, -.infinity] {
            #expect(Table.evaluate(tdb: tdb) == nil)
        }
    }

    @Test("All reconstructed records share endpoint positions and analytic rates")
    func everyBoundary() throws {
        var previous = Table.evaluate(record: 0, x: 1)
        var maximumPosition = 0.0
        var maximumVelocity = 0.0
        for record in 1..<Table.recordCount {
            let next = Table.evaluate(record: record, x: -1)
            maximumPosition = max(maximumPosition, EngineMoonEphemerisTests.largest(next.position - previous.position))
            maximumVelocity = max(maximumVelocity, EngineMoonEphemerisTests.largest(next.velocity - previous.velocity))
            previous = Table.evaluate(record: record, x: 1)
        }
        #expect(maximumPosition < 1e-12)
        #expect(maximumVelocity < 1e-12)
        if let path = ProcessInfo.processInfo.environment["MOON_BOUNDARY_OUTPUT"] {
            let result: [String: Any] = [
                "boundaries": Table.recordCount - 1, "maximumPositionJumpAU": maximumPosition,
                "maximumRateJumpAUPerTDBDay": maximumVelocity,
            ]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(
                to: URL(fileURLWithPath: path))
        }
    }

    @Test("The integrated native model meets the existing allowances at all archived long-span Horizons dates")
    func archivedHorizons() throws {
        for reference in EngineMoonHorizonsTests.vectors {
            let errors = try EngineMoonHorizonsTests.errors(reference)
            #expect(errors.arcminutes <= toleranceArcminutes, "\(reference.tdb): \(errors.arcminutes)")
            #expect(errors.km <= EngineMoonHorizonsTests.distanceAllowanceKm, "\(reference.tdb): \(errors.km)")
        }
    }

    @Test("DE441 analytic rates include the TT to TDB derivative and frame bias")
    func analyticRate() throws {
        for tt in stride(from: -1_460_000.25, through: 1_460_000.25, by: 20_000.0) {
            let actual = try #require(Table.state(tt: tt))
            let step = 1.0 / 64
            func position(_ t: Double) throws -> SIMD3<Double> { try #require(Table.state(tt: t)).position }
            let difference =
                try
                (position(tt - 2 * step) - 8 * position(tt - step) + 8 * position(tt + step) - position(tt + 2 * step))
                / (12 * step)
            let speed = (actual.velocity * actual.velocity).sum().squareRoot()
            #expect(
                EngineMoonEphemerisTests.largest(actual.velocity - difference) <= EngineMoonStatesTests.allowance(
                    tt: tt) * speed)
        }
    }
    @Test("Broad-range direct-source states remain inside the qualified representation bounds")
    func directSourceStates() throws {
        struct Row: Decodable {
            let record: Int
            let x: Double
            let positionKm: [Double]
            let velocityKmPerTDBDay: [Double]
        }
        struct Fixture: Decodable {
            let recordCount: Int
            let rows: [Row]
        }
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("Scripts/moon-data/de441-native-fixtures.json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: data)
        #expect(fixture.recordCount == 273 && fixture.rows.count == 1365)
        var maximumPosition = 0.0
        var maximumVelocity = 0.0
        var maximumIntegratedRate = 0.0
        var maximumAngle = 0.0
        var maximumDistance = 0.0
        var maximumLongitude = 0.0
        var maximumLatitude = 0.0
        var integratedCount = 0
        for row in fixture.rows {
            let actual = Table.evaluate(record: row.record, x: row.x)
            let p =
                actual.position * Engine.kilometersPerAU
                - SIMD3(row.positionKm[0], row.positionKm[1], row.positionKm[2])
            let v =
                actual.velocity * Engine.kilometersPerAU
                - SIMD3(row.velocityKmPerTDBDay[0], row.velocityKmPerTDBDay[1], row.velocityKmPerTDBDay[2])
            maximumPosition = max(maximumPosition, (p * p).sum().squareRoot())
            maximumVelocity = max(maximumVelocity, (v * v).sum().squareRoot())
            let tdb = Table.start + Double(row.record) * 4 + (row.x + 1) * 2
            let tt = tdb - Engine.TDB.offsetSeconds(tt: tdb) / Engine.secondsPerDay
            guard abs(tt) <= Engine.acceptedTTDays else { continue }
            let time = PlanetTestSupport.time(tt: tt)
            let expected = Engine.FrameBias.icrsToEqj.apply(
                to: SIMD3(row.positionKm[0], row.positionKm[1], row.positionKm[2]) / Engine.kilometersPerAU)
            let expectedVelocity = Engine.FrameBias.icrsToEqj.apply(
                to: SIMD3(row.velocityKmPerTDBDay[0], row.velocityKmPerTDBDay[1], row.velocityKmPerTDBDay[2])
                    * Engine.TDB.rate(tt: tt) / Engine.kilometersPerAU)
            let expectedVector = Engine.Vector<Engine.EQJ>(x: expected.x, y: expected.y, z: expected.z, time: time)
            let integrated = try Engine.Moon.geocentricState(at: time)
            let rateError =
                (SIMD3(integrated.vx, integrated.vy, integrated.vz) - expectedVelocity) * Engine.kilometersPerAU
            maximumIntegratedRate = max(maximumIntegratedRate, (rateError * rateError).sum().squareRoot())
            maximumAngle = max(maximumAngle, try integrated.position.angle(to: expectedVector) * 60)
            maximumDistance = max(
                maximumDistance, abs(integrated.position.length - expectedVector.length) * Engine.kilometersPerAU)
            let expectedAngles = Engine.Moon.eclipticAngles(
                Engine.FrameRotation.eqjToEct(time).apply(to: expectedVector))
            let ecliptic = try Engine.Moon.eclipticState(at: time)
            maximumLongitude = max(
                maximumLongitude,
                abs(IndependentReferenceMath.wrappedDifference(ecliptic.longitude, expectedAngles.longitude)) * 60)
            maximumLatitude = max(maximumLatitude, abs(ecliptic.latitude - expectedAngles.latitude) * 60)
            integratedCount += 1
        }
        #expect(maximumPosition <= 18.073)
        #expect(maximumVelocity <= 39.085)
        #expect(integratedCount > 1300)
        #expect(maximumIntegratedRate <= 39.085)
        #expect(maximumAngle <= toleranceArcminutes)
        #expect(maximumDistance <= EngineMoonHorizonsTests.distanceAllowanceKm)
        #expect(maximumLongitude <= toleranceArcminutes)
        #expect(maximumLatitude <= toleranceArcminutes)
        if let path = ProcessInfo.processInfo.environment["MOON_DIFFERENTIAL_OUTPUT"] {
            let result: [String: Any] = [
                "samples": fixture.rows.count, "maximumPositionKm": maximumPosition,
                "maximumRateKmPerTDBDay": maximumVelocity,
                "integratedSamples": integratedCount, "maximumIntegratedRateKmPerTTDay": maximumIntegratedRate,
                "maximumIntegratedAngleArcminutes": maximumAngle, "maximumIntegratedDistanceKm": maximumDistance,
                "maximumLongitudeArcminutes": maximumLongitude, "maximumLatitudeArcminutes": maximumLatitude,
            ]
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(
                to: URL(fileURLWithPath: path))
        }
    }
}

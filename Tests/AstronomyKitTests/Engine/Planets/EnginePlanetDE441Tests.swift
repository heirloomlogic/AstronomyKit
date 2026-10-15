import Foundation
import Testing

@testable import AstronomyKit

@Suite("DE-backed planet source foundation")
struct EnginePlanetDE441Tests {
    typealias Source = Engine.PlanetDE441

    static func norm(_ value: SIMD3<Double>) -> Double { (value * value).sum().squareRoot() }

    @Test("The binary64 table evaluates exact coefficients and analytic rates")
    func tableRecurrence() throws {
        let values: [Double] = [
            1, 2, 3,
            4, 5, 6,
            7, 8, 9,
        ]
        let data = values.withUnsafeBytes { Data($0) }
        let table = Engine.DirectChebyshevTable(
            start: -2, days: 4, recordCount: 1, coefficientCount: 3, scalarBytes: 8, data: data)
        let left = try #require(table.evaluate(tdb: -2))
        let middle = try #require(table.evaluate(tdb: 0))
        let acceleration = try #require(table.acceleration(tdb: 0))
        #expect(left.position == SIMD3(2, 5, 8))
        #expect(middle.position == SIMD3(-2, -2, -2))
        #expect(left.velocity == SIMD3(-5, -9.5, -14))
        #expect(middle.velocity == SIMD3(1, 2.5, 4))
        #expect(acceleration == SIMD3(3, 6, 9))
        #expect(table.evaluate(tdb: (-2.0).nextDown) == nil)
        #expect(table.evaluate(tdb: 2) == nil)
        #expect(table.evaluate(tdb: .nan) == nil)
    }

    @Test("Malformed compiled records fail closed")
    func malformedRecords() {
        let invalidBase64 = Engine.DirectChebyshevTable(
            start: 0, days: 1, recordCount: 1, coefficientCount: 1, recordsPerChunk: 1,
            chunks: ["AAAAAAAA8D8AAAAAAAAAQAAAAAAA!AhA"])
        let truncated = Engine.DirectChebyshevTable(
            start: 0, days: 1, recordCount: 1, coefficientCount: 1, recordsPerChunk: 1, chunks: [""])
        let nonfinite = Engine.DirectChebyshevTable(
            start: 0, days: 1, recordCount: 1, coefficientCount: 1, recordsPerChunk: 1,
            chunks: ["AAAAAAAA8H8AAAAAAAAAQAAAAAAAAAhA"])
        #expect(invalidBase64.evaluate(tdb: 0.5) == nil)
        #expect(truncated.evaluate(tdb: 0.5) == nil)
        #expect(nonfinite.evaluate(tdb: 0.5) == nil)
        #expect(invalidBase64.acceleration(tdb: 0.5) == nil)
        #expect(truncated.acceleration(tdb: 0.5) == nil)
        #expect(nonfinite.acceleration(tdb: 0.5) == nil)
    }

    @Test("Every generated component matches retained direct-source recurrence fixtures")
    func sourceFixtures() throws {
        struct Row: Decodable {
            let component: String
            let record: Int
            let x: Double
            let positionKm: [Double]
            let velocityKmPerTDBDay: [Double]
        }
        struct Fixture: Decodable { let rows: [Row] }
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/planet-data/de441-direct-fixtures.json")))
        #expect(Set(fixture.rows.map(\.component)) == Set(Source.components.keys))
        #expect(fixture.rows.count >= Source.components.count * 9)
        for row in fixture.rows {
            let table = try #require(Source.components[row.component])
            let actual = try #require(table.evaluate(record: row.record, x: row.x))
            let expectedPosition = SIMD3(row.positionKm[0], row.positionKm[1], row.positionKm[2])
            let expectedVelocity = SIMD3(
                row.velocityKmPerTDBDay[0], row.velocityKmPerTDBDay[1], row.velocityKmPerTDBDay[2])
            let positionRoundoff = 64 * Double.ulpOfOne * max(1, Self.norm(expectedPosition))
            let velocityRoundoff = 64 * Double.ulpOfOne * max(1, Self.norm(expectedVelocity))
            #expect(
                Self.norm(actual.position - expectedPosition) <= positionRoundoff,
                "\(row.component) record \(row.record)")
            #expect(
                Self.norm(actual.velocity - expectedVelocity) <= velocityRoundoff,
                "\(row.component) record \(row.record)")
        }
    }

    @Test("Neptune's exact and adjacent offset seam values select their one-sided source records")
    func neptuneOffsetSeam() throws {
        let table = Source.neptuneOffset
        let record = 8_279
        let seam = table.start + Double(record) * table.days
        #expect(seam == -20_000.5)
        for tdb in [seam.nextDown, seam, seam.nextUp] {
            let selected = tdb < seam ? record - 1 : record
            let x = 2 * (tdb - (table.start + Double(selected) * table.days)) / table.days - 1
            let actual = try #require(table.evaluate(tdb: tdb))
            let expected = try #require(table.evaluate(record: selected, x: x))
            #expect(actual.position == expected.position)
            #expect(actual.velocity == expected.velocity)
        }

        var tt = seam
        for _ in 0..<3 { tt = seam - Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay }
        for instant in [tt.nextDown, tt, tt.nextUp] {
            let source = try #require(Source.state(of: .neptune, tt: instant, physicalCenter: true))
            let publicState = try Engine.Planet.neptune.heliocentricState(at: PlanetTestSupport.time(tt: instant))
            #expect(Self.norm(publicState.positionVector - source.position) < 1e-10)
            #expect(Self.norm(publicState.velocityVector - source.velocity) < 2e-14)
        }
    }

    @Test("Source domains include both blends and reject their exterior endpoints")
    func domains() throws {
        let ttBoundaries = [-36_556.5, -36_524.5, 47_846.5, 47_878.5]
        for tt in ttBoundaries {
            let conversion = Engine.TDB.offsetAndRate(tt: tt)
            let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
            for planet in Engine.Planet.allCases {
                #expect(Source.state(of: planet, tt: tt, physicalCenter: true) != nil, "\(planet) at \(tt)")
                #expect(Source.state(of: planet, tt: tt, physicalCenter: false) != nil, "\(planet) at \(tt)")
            }
            #expect(Source.sun.evaluate(tdb: tdb) != nil)
        }
        for table in Source.components.values {
            #expect(table.evaluate(tdb: table.start.nextDown) == nil)
            #expect(table.evaluate(tdb: table.start + Double(table.recordCount) * table.days) == nil)
            #expect(table.evaluate(tdb: .infinity) == nil)
        }
    }

    @Test("Physical-center composition and TT derivatives agree with centered differences")
    func compositionsAndRates() throws {
        for planet in Engine.Planet.allCases {
            for tt in [-36_540.25, -1_234.5, 0, 12_345.25, 47_860.75] {
                let state = try #require(Source.state(of: planet, tt: tt, physicalCenter: true))
                let system = try #require(Source.state(of: planet, tt: tt, physicalCenter: false))
                let h = 1.0 / 128
                func position(_ epoch: Double) throws -> SIMD3<Double> {
                    try #require(Source.state(of: planet, tt: epoch, physicalCenter: true)).position
                }
                let difference =
                    try
                    (position(tt - 2 * h) - 8 * position(tt - h) + 8 * position(tt + h)
                    - position(tt + 2 * h)) / (12 * h)
                #expect(Self.norm(state.velocity - difference) < 5e-10, "\(planet) TT \(tt)")
                if [.earth, .jupiter, .saturn, .uranus, .neptune].contains(planet) {
                    #expect(state.position != system.position)
                } else {
                    #expect(state.position == system.position)
                    #expect(state.velocity == system.velocity)
                }
            }
        }
    }

    @Test("Uranus uses the authorized mixed-source composition")
    func uranusComposition() throws {
        for tt in [11_267.75, 20_000.5, 30_000.25] {
            let conversion = Engine.TDB.offsetAndRate(tt: tt)
            let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
            let barycenter = try #require(Source.uranusBarycenter.evaluate(tdb: tdb))
            let sun = try #require(Source.sun.evaluate(tdb: tdb))
            let offset = try #require(Source.uranusOffset.evaluate(tdb: tdb))
            let actual = try #require(Source.state(of: .uranus, tt: tt, physicalCenter: true))
            let expectedPosition = Engine.FrameBias.icrsToEqj.apply(
                to: (barycenter.position - sun.position + offset.position) / Engine.kilometersPerAU)
            #expect(Self.norm(actual.position - expectedPosition) < 1e-17)
        }
    }

    @Test("Selected-window public-route latency can be recorded")
    func measurement() throws {
        guard let outputPath = ProcessInfo.processInfo.environment["PLANET_DE441_MEASUREMENT_PATH"] else {
            return
        }
        let epochs = [-36_540.25, -1_234.5, 0, 12_345.25, 47_860.75]
        let coldStart = ProcessInfo.processInfo.systemUptime
        var checksum = try Engine.Planet.jupiter.heliocentricState(at: PlanetTestSupport.time(tt: epochs[0])).x
        let coldSeconds = ProcessInfo.processInfo.systemUptime - coldStart
        let iterations = 10_000
        let warmStart = ProcessInfo.processInfo.systemUptime
        for index in 0..<iterations {
            let planet = Engine.Planet.allCases[index % Engine.Planet.allCases.count]
            let state = try planet.heliocentricState(at: PlanetTestSupport.time(tt: epochs[index % epochs.count]))
            checksum += state.x + state.vy
        }
        let warmSeconds = ProcessInfo.processInfo.systemUptime - warmStart
        let report: [String: Any] = [
            "coldJupiterPublicSeconds": coldSeconds,
            "iterations": iterations,
            "meanPublicStateMicroseconds": warmSeconds * 1_000_000 / Double(iterations),
            "checksum": checksum,
        ]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
    }
}

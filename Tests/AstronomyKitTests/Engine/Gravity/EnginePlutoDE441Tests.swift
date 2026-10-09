import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native DE441 Pluto")
struct EnginePlutoDE441Tests {
    typealias Table = Engine.PlutoDE441

    static func length(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }

    @Test("The tables cover the accepted domain, while native entry points retain their strict range")
    func domain() throws {
        #expect(Table.pluto.data.count + Table.sun.data.count == 6_898_944)
        #expect(Table.pluto.recordCount == 47_909 && Table.sun.recordCount == 95_817)
        for tt in [-766_525.0, 766_525.0] {
            #expect(Table.state(tt: tt) != nil)
            _ = try Engine.Pluto.heliocentricState(at: PlanetTestSupport.time(tt: tt))
        }
        for tt in [(-766_525.0).nextDown, 766_525.0.nextUp, .nan, .infinity, -.infinity] {
            #expect(Table.state(tt: tt) == nil)
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Pluto.heliocentricState(at: PlanetTestSupport.time(tt: tt))
            }
        }
        for table in [Table.pluto, Table.sun] {
            #expect(table.evaluate(tdb: table.start.nextDown) == nil)
            #expect(table.evaluate(tdb: table.start + Double(table.recordCount) * table.days) == nil)
            #expect(table.evaluate(tdb: .nan) == nil)
        }
    }

    @Test("Every shared node retains position and analytic-rate continuity")
    func boundaries() throws {
        var position = 0.0
        var rate = 0.0
        var count = 0
        for table in [Table.pluto, Table.sun] {
            var previous = table.evaluate(record: 0, x: 1)
            for index in 1..<table.recordCount {
                let next = table.evaluate(record: index, x: -1)
                position = max(position, Self.length(next.position - previous.position) * Engine.kilometersPerAU)
                rate = max(rate, Self.length(next.velocity - previous.velocity) * Engine.kilometersPerAU)
                previous = table.evaluate(record: index, x: 1)
                count += 1
            }
        }
        // Arithmetic regression checks at the scale established by the decoded Float64 source experiment.
        #expect(position < 0.000_01)
        #expect(rate < 0.000_000_001)
        try Self.write(
            ["count": count, "maximumPositionKm": position, "maximumRateKmPerTDBDay": rate],
            key: "PLUTO_BOUNDARY_OUTPUT")
    }

    @Test("Direct-source fixtures retain the qualified representation bounds and time/frame semantics")
    func directSource() throws {
        struct BodyRow: Decodable {
            let target: Int
            let record: Int
            let x: Double
            let positionKm: [Double]
            let velocityKmPerTDBDay: [Double]
        }
        struct StateRow: Decodable {
            let tdb: Double
            let positionKm: [Double]
            let velocityKmPerTDBDay: [Double]
        }
        struct Fixture: Decodable {
            let bodyRows: [BodyRow]
            let heliocentricRows: [StateRow]
        }
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/pluto-data/de441-native-fixtures.json")))
        #expect(fixture.bodyRows.count == 4305 && fixture.heliocentricRows.count == 72)
        func vector(_ a: [Double]) -> SIMD3<Double> { SIMD3(a[0], a[1], a[2]) }
        var position = 0.0
        var rate = 0.0
        for row in fixture.bodyRows {
            let table = row.target == 9 ? Table.pluto : Table.sun
            let state = table.evaluate(record: row.record, x: row.x)
            let p = Self.length(state.position * Engine.kilometersPerAU - vector(row.positionKm))
            let v = Self.length(state.velocity * Engine.kilometersPerAU - vector(row.velocityKmPerTDBDay))
            position = max(position, p)
            rate = max(rate, v)
            // Sum-of-bodies bounds, rounded up from the qualified evidence; these check representation, not physical-center accuracy.
            #expect(p <= 0.234_914 && v <= 0.134_200)
        }
        var integratedPosition = 0.0
        var integratedRate = 0.0
        var integratedCount = 0
        var maximumAngle = 0.0
        for row in fixture.heliocentricRows {
            var tt = row.tdb
            for _ in 0..<3 { tt = row.tdb - Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay }
            guard abs(tt) <= 766_525 else { continue }
            let state = try #require(Table.state(tt: tt))
            let expected = Engine.FrameBias.icrsToEqj.apply(to: vector(row.positionKm) / Engine.kilometersPerAU)
            let velocity = Engine.FrameBias.icrsToEqj.apply(
                to: vector(row.velocityKmPerTDBDay) * Engine.TDB.rate(tt: tt) / Engine.kilometersPerAU)
            #expect(Self.length(state.position - expected) * Engine.kilometersPerAU <= 0.234_914)
            #expect(Self.length(state.velocity - velocity) * Engine.kilometersPerAU <= 0.134_200)
            guard Engine.MoonEphemeris.weight(tt: tt).weight == 0 else { continue }
            let time = PlanetTestSupport.time(tt: tt)
            let native = try Engine.Pluto.heliocentricState(at: time)
            integratedPosition = max(
                integratedPosition, Self.length(SIMD3(native.x, native.y, native.z) - expected) * Engine.kilometersPerAU
            )
            integratedRate = max(
                integratedRate, Self.length(SIMD3(native.vx, native.vy, native.vz) - velocity) * Engine.kilometersPerAU)
            let actual = SIMD3(native.x, native.y, native.z)
            let cross = SIMD3(
                actual.y * expected.z - actual.z * expected.y, actual.z * expected.x - actual.x * expected.z,
                actual.x * expected.y - actual.y * expected.x)
            let angle = atan2(Self.length(cross), (actual * expected).sum()) * 180 / .pi * 60
            maximumAngle = max(maximumAngle, angle)
            integratedCount += 1
        }
        #expect(integratedCount == 48)
        #expect(integratedPosition <= 0.234_914 && integratedRate <= 0.134_200)
        #expect(maximumAngle <= toleranceArcminutes)
        try Self.write(
            [
                "bodySamples": fixture.bodyRows.count, "maximumBodyPositionKm": position,
                "maximumBodyRateKmPerTDBDay": rate, "integratedSamples": integratedCount,
                "maximumIntegratedPositionKm": integratedPosition, "maximumIntegratedRateKmPerTTDay": integratedRate,
                "maximumIntegratedAngleArcminutes": maximumAngle,
            ], key: "PLUTO_DIFFERENTIAL_OUTPUT")
    }

    @Test("Analytic rates differentiate both bodies, TT/TDB, and the frame transform")
    func derivative() throws {
        for tt in stride(from: -760_000.25, through: 760_000.25, by: 20_000) {
            let state = try #require(Table.state(tt: tt))
            let h = 1.0 / 16
            func p(_ t: Double) throws -> SIMD3<Double> { try #require(Table.state(tt: t)).position }
            let difference = try (p(tt - 2 * h) - 8 * p(tt - h) + 8 * p(tt + h) - p(tt + 2 * h)) / (12 * h)
            // Same finite-difference allowance as the existing native Pluto state checks.
            #expect(EngineMoonEphemerisTests.largest(state.velocity - difference) <= 2e-9)
        }
    }

    @Test("Archived center and barycenter residuals keep their physical meaning")
    func archivedResiduals() throws {
        typealias References = PlutoSegmentSuites.EnginePlutoHorizonsTests
        let references = References.vectors + References.barycenterVectors
        #expect(references.count == 44)
        var rows: [[String: Any]] = []
        for reference in references {
            let tt = References.tt(reference)
            let state = try References.state(reference)
            let expected = References.expected(reference)
            let rawVelocity = reference.velocityAUPerDay
            let velocity = Engine.FrameBias.icrsToEqj.apply(
                to: SIMD3(rawVelocity[0], rawVelocity[1], rawVelocity[2]) * Engine.TDB.rate(tt: tt))
            let angle = try References.arcminutes(SIMD3(state.x, state.y, state.z), reference)
            #expect(angle <= toleranceArcminutes)
            rows.append([
                "julianDateTDB": reference.julianDateTDB, "body": reference.body,
                "centerWeight": Engine.MoonEphemeris.weight(tt: tt).weight,
                "positionDifferenceKm": Self.length(SIMD3(state.x, state.y, state.z) - expected)
                    * Engine.kilometersPerAU,
                "velocityDifferenceKmPerSecond": Self.length(SIMD3(state.vx, state.vy, state.vz) - velocity)
                    * Engine.kilometersPerAU / Engine.secondsPerDay, "angularDifferenceArcminutes": angle,
            ])
        }
        try Self.write(["rows": rows], key: "PLUTO_REFERENCE_OUTPUT")
    }

    static func write(_ value: [String: Any], key: String) throws {
        if let path = ProcessInfo.processInfo.environment[key] {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
                to: URL(fileURLWithPath: path))
        }
    }
}

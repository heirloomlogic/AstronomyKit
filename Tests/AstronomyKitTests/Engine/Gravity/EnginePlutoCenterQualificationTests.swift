import Foundation
import Testing

@testable import AstronomyKit

@Suite("Complete PLU060 center qualification")
struct EnginePlutoCenterQualificationTests {
    typealias Center = Engine.PlutoEphemeris
    struct Row: Decodable {
        let tdb: Double
        let positionKm: [Double]
        let velocityKmPerTDBDay: [Double]
    }
    struct Blend: Decodable {
        let startTDB: Double
        let endTDB: Double
        let positionBoundKm: Double
        let rateBoundKmPerTDBDay: Double
        let angularBoundArcminutes: Double
    }
    struct Fixture: Decodable {
        let directSourceRows: [Row]
        let horizonsRows: [Row]
        let blends: [Blend]
    }
    static func fixture() throws -> Fixture {
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        return try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/pluto-data/plu060-qualification.json")))
    }
    static func tt(_ tdb: Double) -> Double {
        var result = tdb
        for _ in 0..<3 { result = tdb - Engine.TDB.offsetSeconds(tt: result) / Engine.secondsPerDay }
        return result
    }
    static func norm(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }
    static func expected(_ values: [Double]) -> SIMD3<Double> {
        Engine.FrameBias.icrsToEqj.apply(to: SIMD3(values[0], values[1], values[2]) / Engine.kilometersPerAU)
    }

    @Test("Expanded tables preserve independent source states, including both SPK segment and coverage edges")
    func directSource() throws {
        let fixture = try Self.fixture()
        #expect(fixture.directSourceRows.count >= 280)
        #expect(fixture.horizonsRows.count == 19)
        for (rows, positionLimitKm, rateLimit, relativeRate) in [
            (fixture.directSourceRows, 0.000_1, 0.000_01, false),
            (fixture.horizonsRows, 1.0, 1e-8, true),
        ] {
            for row in rows {
                let tt = Self.tt(row.tdb)
                let state = try #require(Center.heliocentricState(tt: tt))
                let positionError = Self.norm(state.position - Self.expected(row.positionKm)) * Engine.kilometersPerAU
                let rateError =
                    Self.norm(
                        state.velocity - Self.expected(row.velocityKmPerTDBDay) * Engine.TDB.rate(tt: tt))
                    * Engine.kilometersPerAU
                let rateLimitKmPerDay =
                    relativeRate
                    ? rateLimit * Self.norm(Self.expected(row.velocityKmPerTDBDay)) * Engine.kilometersPerAU
                    : rateLimit
                #expect(positionError <= positionLimitKm, "TDB \(row.tdb): \(positionError) km")
                #expect(rateError <= rateLimitKmPerDay, "TDB \(row.tdb): \(rateError) km/TT day")
                let time = Engine.Time(tt: tt, deltaTModel: .jplHorizons)
                let integrated = try Engine.Pluto.heliocentricState(at: time)
                if Center.weight(tt: tt).weight == 1 {
                    #expect(SIMD3(integrated.x, integrated.y, integrated.z) == state.position)
                    #expect(SIMD3(integrated.vx, integrated.vy, integrated.vz) == state.velocity)
                }
            }
        }
    }

    @Test("Both complete blend intervals have bounded center error and an analytic TT derivative")
    func blends() throws {
        let fixture = try Self.fixture()
        #expect(fixture.blends.count == 2)
        for blend in fixture.blends {
            #expect(blend.angularBoundArcminutes < 1)
            for index in 0...128 {
                let tdb = blend.startTDB + (blend.endTDB - blend.startTDB) * Double(index) / 128
                let tt = Self.tt(tdb)
                func state(_ t: Double) throws -> Engine.State<Engine.EQJ> {
                    try Engine.Pluto.heliocentricState(at: Engine.Time(tt: t, deltaTModel: .jplHorizons))
                }
                let mixed = try state(tt)
                if let source = Center.heliocentricState(tt: tt) {
                    let positionError =
                        Self.norm(SIMD3(mixed.x, mixed.y, mixed.z) - source.position) * Engine.kilometersPerAU
                    let rateError =
                        Self.norm(SIMD3(mixed.vx, mixed.vy, mixed.vz) - source.velocity) * Engine.kilometersPerAU
                    #expect(positionError <= blend.positionBoundKm + 0.000_1)
                    #expect(rateError <= blend.rateBoundKmPerTDBDay * Engine.TDB.rate(tt: tt) + 0.000_01)
                }
                let h = 1.0 / 256
                func position(_ t: Double) throws -> SIMD3<Double> {
                    let s = try state(t)
                    return SIMD3(s.x, s.y, s.z)
                }
                let difference =
                    (try position(tt - 2 * h) - 8 * position(tt - h) + 8 * position(tt + h) - position(tt + 2 * h))
                    / (12 * h)
                #expect(Self.norm(difference - SIMD3(mixed.vx, mixed.vy, mixed.vz)) <= 2e-9)
            }
        }
    }

    @Test("Source guards and weights use TDB at both edges, with no extrapolation")
    func sourceEdges() throws {
        for edge in [Center.sourceStartTDB, Center.sourceEndTDB] {
            for delta in [-0.000_001, 0.000_001] {
                let tdb = edge + delta
                let tt = Self.tt(tdb)
                let actualTDB = tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay
                #expect(abs(actualTDB - tdb) < 1e-10)
                let inside = tdb > Center.sourceStartTDB && tdb < Center.sourceEndTDB
                #expect((Center.heliocentricState(tt: tt) != nil) == inside)
                #expect((Center.weight(tt: tt).weight > 0) == inside)
                let s = try Engine.Pluto.heliocentricState(at: Engine.Time(tt: tt, deltaTModel: .jplHorizons))
                #expect(s.x.isFinite && s.vx.isFinite)
            }
        }
    }
}

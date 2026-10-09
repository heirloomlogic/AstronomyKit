import Foundation
import Testing

@testable import AstronomyKit

@Suite("Saturn physical-center ephemeris")
struct EngineSaturnEphemerisTests {
    typealias Source = Engine.SaturnEphemeris
    static func norm(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }
    static func p<F>(_ s: Engine.State<F>) -> SIMD3<Double> { SIMD3(s.x, s.y, s.z) }
    static func v<F>(_ s: Engine.State<F>) -> SIMD3<Double> { SIMD3(s.vx, s.vy, s.vz) }
    static func time(_ tt: Double) -> Engine.Time { Engine.Time(tt: tt, deltaTModel: .jplHorizons) }

    @Test("Packed source records preserve their independently bounded coefficient precision")
    func sourceRecords() throws {
        struct Row: Decodable {
            let target: Int
            let record: Int
            let x: Double
            let positionKm: [Double]
            let velocityKmPerTDBDay: [Double]
        }
        struct Fixture: Decodable { let rows: [Row] }
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/saturn-data/direct-fixtures.json")))
        #expect(fixture.rows.count >= 1161)
        var maxPosition = 0.0
        var maxRate = 0.0
        for row in fixture.rows {
            let table = row.target == 6 ? Source.barycenter : row.target == 10 ? Source.sun : Source.offset
            let actual = table.evaluate(record: row.record, x: row.x)
            let expectedP = SIMD3(row.positionKm[0], row.positionKm[1], row.positionKm[2])
            let expectedV = SIMD3(row.velocityKmPerTDBDay[0], row.velocityKmPerTDBDay[1], row.velocityKmPerTDBDay[2])
            let pe = Self.norm(actual.position - expectedP)
            let ve = Self.norm(actual.velocity - expectedV)
            // Rounded-up full-record coefficient bounds, plus Float64 evaluation roundoff.
            let roundingP = 64 * Double.ulpOfOne * max(1, Self.norm(expectedP))
            let roundingV = 64 * Double.ulpOfOne * max(1, Self.norm(expectedV))
            #expect(pe <= (row.target == 699 ? 0.000019734 : 0) + roundingP)
            #expect(ve <= (row.target == 699 ? 0.000007304 : 0) + roundingV)
            maxPosition = max(maxPosition, pe)
            maxRate = max(maxRate, ve)
        }
        #expect(Source.barycenter.data.count + Source.sun.data.count + Source.offset.data.count == 10_618_464)
        for table in [Source.barycenter, Source.sun, Source.offset] {
            #expect(table.evaluate(tdb: table.start.nextDown) == nil)
            #expect(table.evaluate(tdb: table.start + Double(table.recordCount) * table.days) == nil)
            #expect(table.evaluate(tdb: .nan) == nil)
        }
        try EnginePlanetaryEventTests.write(
            ["rows": fixture.rows.count, "maximumPositionKm": maxPosition, "maximumRateKmPerTDBDay": maxRate],
            environment: "SATURN_SOURCE_OUTPUT")
    }

    @Test("System-mass consumers exclude the physical-center offset")
    func systemMassConsumers() throws {
        // DE441 target 6 minus target 10, independently composed from the source tables.
        // sourceRecords checks those tables against direct source recurrence fixtures.
        for tt in [-36556.5, -36540.5, -36524.5, 0, 12020.54855741, 47846.5, 47862.5, 47878.5] {
            let time = Self.time(tt)
            let (weight, rate) = Source.weight(tt: tt)
            let old = try Engine.Planet.saturn.retainedEclipticState(at: time)
            var bp = Self.p(old)
            var bv = Self.v(old)
            if weight > 0 {
                let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay
                let b = try #require(Source.barycenter.evaluate(tdb: tdb))
                let sun = try #require(Source.sun.evaluate(tdb: tdb))
                let p = Engine.FrameBias.icrsToEqj.apply(to: (b.position - sun.position) / Engine.kilometersPerAU)
                let v = Engine.FrameBias.icrsToEqj.apply(
                    to: (b.velocity - sun.velocity) * Engine.TDB.rate(tt: tt) / Engine.kilometersPerAU)
                let state = Engine.State<Engine.EQJ>(x: p.x, y: p.y, z: p.z, vx: v.x, vy: v.y, vz: v.z, time: time)
                let ecliptic = Engine.VSOP87B.toEquatorial.inverse.apply(to: state)
                bv += weight * (Self.v(ecliptic) - bv) + rate * (Self.p(ecliptic) - bp)
                bp += weight * (Self.p(ecliptic) - bp)
            }
            let expected = Engine.VSOP87B.toEquatorial.apply(
                to: Engine.State<Engine.VSOP87Ecliptic>(
                    x: bp.x, y: bp.y, z: bp.z, vx: bv.x, vy: bv.y, vz: bv.z, time: time))
            let physical = try Engine.Planet.saturn.heliocentricState(at: time)
            for planets in [Engine.Gravity.MajorBodies.planets, Engine.Gravity.SolarSystem.planetsWithGM] {
                var offsetP = SIMD3<Double>.zero
                var offsetV = SIMD3<Double>.zero
                var states: [Engine.Gravity.BodyState] = []
                for (planet, gm) in planets {
                    let state = try planet == .saturn ? expected : planet.heliocentricState(at: time)
                    let shift = gm / (gm + Engine.Gravity.sunGM)
                    offsetP += shift * Self.p(state)
                    offsetV += shift * Self.v(state)
                    states.append(.init(position: Self.p(state), velocity: Self.v(state)))
                }
                let major = try Engine.Gravity.MajorBodies(tt: tt)
                let solar = try Engine.Gravity.SolarSystem(tt: tt)
                let sun = planets.count == 4 ? major.sun : solar.sun
                #expect(Self.norm(sun.position + offsetP) < 1e-17)
                #expect(Self.norm(sun.velocity + offsetV) < 1e-20)
                let saturn = planets.count == 4 ? major.saturn : solar.planets[Engine.Planet.saturn.rawValue]
                #expect(Self.norm(saturn.position + offsetP - Self.p(expected)) < 4e-15)
                #expect(Self.norm(saturn.velocity + offsetV - Self.v(expected)) < 4e-18)
                let point = SIMD3(1.2, -0.4, 0.3)
                var acceleration = Engine.Gravity.pull(of: Engine.Gravity.sunGM, at: -offsetP, on: point)
                for (state, pair) in zip(states, planets) {
                    acceleration += Engine.Gravity.pull(of: pair.1, at: state.position - offsetP, on: point)
                }
                let actual = planets.count == 4 ? major.acceleration(at: point) : solar.acceleration(at: point)
                #expect(Self.norm(actual - acceleration) < 1e-20)
            }
            let major = try Engine.Gravity.MajorBodies(tt: tt)
            let ssb = try Engine.Positions.heliocentricState(of: .solarSystemBarycenter, at: time)
            let ssbPosition = try Engine.Positions.heliocentricPosition(of: .solarSystemBarycenter, at: time)
            #expect(Self.p(ssb) == SIMD3(ssbPosition.x, ssbPosition.y, ssbPosition.z))
            #expect(Self.p(ssb) == -major.sun.position && Self.v(ssb) == -major.sun.velocity)
            let bary = try Engine.Positions.barycentricState(of: .saturn, at: time)
            #expect(Self.norm(Self.p(bary) - major.sun.position - Self.p(physical)) < 4e-15)
            #expect(Self.norm(Self.v(bary) - major.sun.velocity - Self.v(physical)) < 4e-18)
            let solar = try Engine.Gravity.SolarSystem(tt: tt)
            let exposed = try #require(solar.state(of: .saturn))
            #expect(Self.norm(exposed.position - solar.sun.position - Self.p(physical)) < 4e-15)
            #expect(Self.norm(exposed.velocity - solar.sun.velocity - Self.v(physical)) < 4e-18)
        }
    }

    @Test("Exact blend endpoints, source padding, and derivatives preserve consumer semantics")
    func transitions() throws {
        let boundaries = [-36556.5, -36524.5, 47846.5, 47878.5]
        #expect(Source.weight(tt: boundaries[0]).weight == 0)
        #expect(Source.weight(tt: boundaries[1]).weight == 1)
        #expect(Source.weight(tt: boundaries[2]).weight == 1)
        #expect(Source.weight(tt: boundaries[3]).weight == 0)
        for tt in boundaries + [-36540.5, 0, 47862.5] {
            for delta in [-0.001, 0, 0.001] {
                let epoch = tt + delta
                let state = try Engine.Planet.saturn.heliocentricEclipticState(at: Self.time(epoch))
                let position = try Engine.Planet.saturn.heliocentricEclipticPosition(at: Self.time(epoch))
                #expect(Self.p(state) == SIMD3(position.x, position.y, position.z))
                let distance = try Engine.Planet.saturn.heliocentricDistance(at: Self.time(epoch))
                if Source.weight(tt: epoch).weight > 0 {
                    #expect(distance == position.length)
                } else {
                    // The retained VSOP radius and Cartesian norm have the existing rounding allowance.
                    #expect(abs(distance - position.length) <= 4e-16 * distance)
                }
                let h = 1.0 / 128
                func at(_ t: Double) throws -> SIMD3<Double> {
                    Self.p(try Engine.Planet.saturn.heliocentricEclipticState(at: Self.time(t)))
                }
                let derivative =
                    try (at(epoch - 2 * h) - 8 * at(epoch - h) + 8 * at(epoch + h) - at(epoch + 2 * h)) / (12 * h)
                #expect(Self.norm(Self.v(state) - derivative) < 2e-9)
                let systemState = try Engine.Planet.saturn.systemHeliocentricState(at: Self.time(epoch))
                func systemAt(_ t: Double) throws -> SIMD3<Double> {
                    Self.p(try Engine.Planet.saturn.systemHeliocentricState(at: Self.time(t)))
                }
                let systemDerivative =
                    try
                    (systemAt(epoch - 2 * h) - 8 * systemAt(epoch - h) + 8 * systemAt(epoch + h)
                    - systemAt(epoch + 2 * h)) / (12 * h)
                #expect(Self.norm(Self.v(systemState) - systemDerivative) < 2e-9)
                if Source.weight(tt: epoch).weight == 0 {
                    let old = try Engine.Planet.saturn.retainedEclipticState(at: Self.time(epoch))
                    #expect(Self.p(old) == Self.p(state) && Self.v(old) == Self.v(state))
                } else {
                    #expect(Source.eclipticState(at: Self.time(epoch)) != nil)
                }
            }
            let left = try Engine.Planet.saturn.heliocentricEclipticState(at: Self.time(tt - 1e-6))
            let right = try Engine.Planet.saturn.heliocentricEclipticState(at: Self.time(tt + 1e-6))
            #expect(Self.norm(Self.p(right) - Self.p(left)) < 2e-8)
            #expect(Self.norm(Self.v(right) - Self.v(left)) < 2e-9)
        }
        for tt in [-1_461_000.0, 1_461_000.0] {
            let actual = try Engine.Planet.saturn.heliocentricEclipticState(at: Self.time(tt))
            let old = try Engine.Planet.saturn.retainedEclipticState(at: Self.time(tt))
            #expect(Self.p(actual) == Self.p(old) && Self.v(actual) == Self.v(old))
            let system = try Engine.Planet.saturn.systemHeliocentricState(at: Self.time(tt))
            let retained = Engine.VSOP87B.toEquatorial.apply(to: old)
            #expect(Self.p(system) == Self.p(retained) && Self.v(system) == Self.v(retained))
        }
        for tt in [Double.nan, .infinity, -.infinity, 1_461_001] {
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Planet.saturn.heliocentricState(at: Self.time(tt))
            }
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Planet.saturn.systemHeliocentricState(at: Self.time(tt))
            }
        }
    }
}

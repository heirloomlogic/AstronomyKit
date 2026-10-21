//
//  AcceptedTimeRangeTests.swift
//  AstronomyKit
//
//  Tests for the ephemeris models' accepted time range (#62).
//

import Testing

@testable import AstronomyKit

/// The ephemeris models accept a Terrestrial Time within 4000 Julian years of
/// J2000 (`|tt| <= 1_461_000` days). Outside it they used to report success with
/// absurd values (a negative distance for Mars at `ut: 1e10`) and then NaN (every
/// distance at `ut: 1e300`); they now throw `badTime`.
@Suite("Accepted Time Range")
struct AcceptedTimeRangeTests {
    static let limit = 1_461_000.0

    /// Bodies with their own heliocentric model or a trivial one. Pluto is
    /// tested separately because its own range is narrower.
    static let bodies: [CelestialBody] = [
        .sun, .moon, .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune,
    ]

    /// `AstroTime(ut: -1e15)` has a TT of about +2.8e17, and `-1e300` an
    /// infinite TT, because Espenak-Meeus Delta T grows as the square of the
    /// time. Both are rejected either way.
    static let farTimes: [Double] = [1e300, -1e300, 1e15, -1e15, 1e8, -1e8]

    // MARK: - Far Outside the Range

    @Test("Position, distance, and state functions throw badTime far outside the range", arguments: farTimes)
    func bodyFunctionsThrow(ut: Double) {
        let time = AstroTime(ut: ut)
        for body in Self.bodies + [.pluto] {
            #expect(throws: AstronomyError.badTime, "\(body) heliocentric") {
                _ = try body.heliocentricPosition(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) distance") {
                _ = try body.distanceFromSun(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) heliocentric state") {
                _ = try body.heliocentricState(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) barycentric state") {
                _ = try body.barycentricState(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) geocentric") {
                _ = try body.geocentricPosition(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) equatorial") {
                _ = try body.equatorial(at: time)
            }
        }
        for body in [CelestialBody.sun, .moon, .mars, .neptune] {
            #expect(throws: AstronomyError.badTime, "\(body) ecliptic state") {
                _ = try body.geocentricEclipticState(at: time)
            }
        }
    }

    @Test("Sun, Moon, and Jupiter's moons throw badTime far outside the range", arguments: farTimes)
    func sunMoonThrow(ut: Double) {
        let time = AstroTime(ut: ut)
        #expect(throws: AstronomyError.badTime) { _ = try Sun.position(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Sun.eclipticState(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.geocentricPosition(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.ecliptic(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.eclipticState(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.geoState(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.phaseAngle(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Jupiter.moons(at: time) }
    }

    /// The issue's cases: Neptune's apsis search used to return its start time
    /// with a NaN distance at `ut: 1e300`, a 3.8e40 AU distance at `1e15`, and
    /// -1068 AU at `1e8`; Mars returned 11,499 AU at `1e8`.
    @Test("Apsis and node searches throw badTime far outside the range", arguments: farTimes)
    func searchesThrow(ut: Double) {
        let time = AstroTime(ut: ut)
        for body in [CelestialBody.mercury, .mars, .jupiter, .neptune, .pluto] {
            #expect(throws: AstronomyError.badTime, "\(body)") {
                _ = try body.searchApsis(after: time)
            }
        }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.searchApsis(after: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.searchNode(after: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.searchQuarter(after: time) }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.sun.riseTime(after: time, from: .primeMeridian, limitDays: 1)
        }
    }

    // MARK: - At the Boundary

    @Test("Heliocentric positions and distances at exactly ±1,461,000 TT days succeed", arguments: [1.0, -1.0])
    func boundaryIsInside(sign: Double) throws {
        let time = AstroTime(tt: sign * Self.limit)
        for body in Self.bodies {
            let position = try body.heliocentricPosition(at: time)
            #expect(position.x.isFinite && position.y.isFinite && position.z.isFinite, "\(body)")
            let distance = try body.distanceFromSun(at: time)
            #expect(distance.isFinite, "\(body)")
            if body != .sun {
                #expect(distance > 0.25 && distance < 35, "\(body): \(distance) AU")
            }
        }
        _ = try Moon.geocentricPosition(at: time)
        _ = try Moon.ecliptic(at: time)
        _ = try Jupiter.moons(at: time)
    }

    @Test("Just outside ±1,461,000 TT days throws badTime", arguments: [1.0, -1.0])
    func justOutsideThrows(sign: Double) {
        let time = AstroTime(tt: sign * Self.limit.nextUp)
        for body in Self.bodies {
            #expect(throws: AstronomyError.badTime, "\(body) heliocentric") {
                _ = try body.heliocentricPosition(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) distance") {
                _ = try body.distanceFromSun(at: time)
            }
        }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.geocentricPosition(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.ecliptic(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Jupiter.moons(at: time) }
    }

    /// Geocentric positions look back by the light time, so a day inside the
    /// edge is safely inside for every body.
    @Test("Geocentric positions and states a day inside the boundary succeed", arguments: [1.0, -1.0])
    func geocentricJustInside(sign: Double) throws {
        let time = AstroTime(tt: sign * (Self.limit - 1))
        for body in Self.bodies where body != .earth {
            let position = try body.geocentricPosition(at: time)
            #expect(position.x.isFinite && position.y.isFinite && position.z.isFinite, "\(body)")
            _ = try body.geocentricEclipticState(at: time)
            _ = try body.heliocentricState(at: time)
        }
        _ = try Sun.position(at: time)
        _ = try Moon.geoState(at: time)
    }

    /// A search that steps past the edge fails there. The node search used to
    /// treat the Moon's latitude as infallible; with a NaN latitude it would
    /// never find a crossing and kept stepping.
    @Test("Searches that step past the boundary throw badTime")
    func searchSteppingOutThrows() {
        let nearEnd = AstroTime(tt: Self.limit - 1)
        #expect(throws: AstronomyError.badTime) { _ = try Moon.searchNode(after: nearEnd) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.searchApsis(after: nearEnd) }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.neptune.searchApsis(after: AstroTime(tt: Self.limit - 10_000))
        }
    }

    // MARK: - Pluto

    /// Pluto's own range (the state table plus about 100 years) lies inside the
    /// accepted range, and the new check does not widen it.
    @Test("Pluto keeps its narrower range", arguments: [800_000.0, -800_000.0, 1_400_000.0])
    func plutoRangeUnchanged(tt: Double) throws {
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.heliocentricPosition(at: AstroTime(tt: tt))
        }
        _ = try CelestialBody.mars.heliocentricPosition(at: AstroTime(tt: tt))
    }

    // MARK: - Gravity Simulation

    @Test("Gravity simulation rejects a time outside the range and keeps its state")
    func gravitySimulation() throws {
        let start = AstroTime(tt: Self.limit - 10)
        // A small body at the Sun-Earth L4 point, clear of every gravitating body.
        let state = try LagrangePoint.calculate(point: .l4, at: start, majorBody: .sun, minorBody: .earth)

        #expect(throws: AstronomyError.badTime) {
            _ = try GravitySimulation(origin: .sun, time: AstroTime(tt: Self.limit.nextUp), initialState: state)
        }

        let simulation = try GravitySimulation(origin: .sun, time: start, initialState: state)
        #expect(throws: AstronomyError.badTime) {
            try simulation.update(to: AstroTime(tt: Self.limit + 1))
        }
        #expect(simulation.time.terrestrialTime == start.terrestrialTime)
        let stepped = try simulation.update(to: AstroTime(tt: Self.limit))
        #expect(stepped.position.x.isFinite)
    }
}

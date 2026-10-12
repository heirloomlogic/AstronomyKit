//
//  EnginePlanetPositionsTests.swift
//  AstronomyKit
//
//  Heliocentric planet positions, states and distances against IMCCE's
//  VSOP87B check values and JPL Horizons, on the polynomial and series paths.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine planet positions")
struct EnginePlanetPositionsTests {
    static func time(tt: Double) -> Engine.Time { PlanetTestSupport.time(tt: tt) }

    static func cache() -> Engine.VSOP87B.Cache { PlanetTestSupport.makeCache().0 }

    static func norm(_ value: SIMD3<Double>) -> Double { (value * value).sum().squareRoot() }

    // MARK: - IMCCE check values

    /// Rectangular position and velocity from the published longitude,
    /// latitude, radius and their rates, on the VSOP87 axes.
    static func rectangular(_ record: PublishedVSOP87.Record) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let (l, b, r) = (record.longitude, record.latitude, record.radius)
        let position = SIMD3(r * cos(b) * cos(l), r * cos(b) * sin(l), r * sin(b))
        let (dl, db, dr) = (record.longitudeRate, record.latitudeRate, record.radiusRate)
        // One product per line, so Swift 6.2 on Linux type-checks it in time.
        let radial: Double = dr * cos(b)
        let tangential: Double = r * cos(b) * dl
        let meridional: Double = r * sin(b) * db
        let vx: Double = radial * cos(l) - meridional * cos(l) - tangential * sin(l)
        let vy: Double = radial * sin(l) - meridional * sin(l) + tangential * cos(l)
        let vz: Double = dr * sin(b) + r * cos(b) * db
        return (position, SIMD3(vx, vy, vz))
    }

    /// The printed angles and radius are each within 5e-11 of the series, and
    /// the published computation rounds longitude by up to about 3e-11 more,
    /// so a component is within about 1e-10 × (1 + 2r) AU and a velocity
    /// component within about 1e-10 × (1 + 2r) AU per day plus the rates'
    /// share of the angle error, which is far smaller. Fits add under 1e-12 AU.
    static func allowance(radius: Double) -> Double { 1e-10 * (1 + 2 * radius) }

    @Test(
        "Retained polynomial/VSOP position and velocity against IMCCE vsop87.chk",
        arguments: PublishedVSOP87.records)
    func publishedEcliptic(record: PublishedVSOP87.Record) throws {
        let polynomial = Engine.PlanetPolynomial.position(record.planet, tt: record.tt) != nil
        #expect(polynomial == (record.tt == 0))
        let cache = Self.cache()
        let state = try record.planet.retainedEclipticState(at: Self.time(tt: record.tt), cache: cache)
        let expected = Self.rectangular(record)
        let allowance = Self.allowance(radius: record.radius)
        for (axis, (actual, published)) in zip(
            [state.x, state.y, state.z], [expected.position.x, expected.position.y, expected.position.z]
        ).enumerated() {
            #expect(abs(actual - published) <= allowance, "position axis \(axis)")
        }
        for (axis, (actual, published)) in zip(
            [state.vx, state.vy, state.vz], [expected.velocity.x, expected.velocity.y, expected.velocity.z]
        ).enumerated() {
            #expect(abs(actual - published) <= allowance, "velocity axis \(axis)")
        }
        #expect((cache.coordinates[record.planet.rawValue].statistics.misses == 0) == polynomial)
    }

    @Test("The rotation to EQJ is the one in vsop87.doc")
    func rotation() {
        let rotation = Engine.VSOP87B.toEquatorial
        // vsop87.doc prints rows of the matrix that takes VSOP87A (x, y, z) to FK5 J2000.
        let printed: [[Double]] = [
            [1.000000000000, 0.000000440360, -0.000000190919],
            [-0.000000479966, 0.917482137087, -0.397776982902],
            [0.000000000000, 0.397776982902, 0.917482137087],
        ]
        for row in 0..<3 {
            for column in 0..<3 {
                // Component `row` of the result is Σ rot[column][row]·v[column].
                #expect(rotation[column, row] == printed[row][column], "row \(row) column \(column)")
            }
        }
    }

    // MARK: - JPL Horizons

    /// 1 arcminute is the accuracy `JPLValidationTests` applies to every
    /// geocentric planet. The largest angle here is 2.4″, for Neptune; VSOP87 was fitted
    /// to DE200, and Horizons uses DE441 in the ICRF. A wrong frame or a swapped
    /// axis moves the direction by degrees.
    @Test("EQJ direction and distance against the JPL Horizons held-out vectors, on both paths")
    func horizons() throws {
        #expect(PlanetTestSupport.heliocentric.count == 1_072)
        let cache = Self.cache()
        var seriesRecords = 0
        for (planet, reference) in PlanetTestSupport.heliocentric {
            let tt = reference.julianDateTT - 2_451_545
            if Engine.PlanetPolynomial.position(planet, tt: tt) == nil { seriesRecords += 1 }
            let time = Self.time(tt: tt)
            let position = try planet.heliocentricPosition(at: time, cache: cache)
            let published = reference.referencePositionAU
            let horizons = Engine.Vector<Engine.EQJ>(x: published[0], y: published[1], z: published[2], time: time)
            let arcseconds = try position.angle(to: horizons) * 3_600
            #expect(arcseconds <= 60, "\(planet) JD TT \(reference.julianDateTT): \(arcseconds)″")
            let distance = try planet.heliocentricDistance(at: time, cache: cache)
            let errorKm = abs(distance - reference.referenceRangeAU) * Engine.kilometersPerAU
            #expect(errorKm <= reference.allowedErrorKm, "\(planet) JD TT \(reference.julianDateTT): \(errorKm) km")
        }
        // The records in excluded segments, which the series cover.
        #expect(seriesRecords == 5)
    }

    @Test("Every selected-window public and system trajectory uses its DE physical center")
    func selectedWindowRouting() throws {
        for planet in Engine.Planet.allCases {
            for tt in [-20_000.25, 0, 40_000.75] {
                let time = Self.time(tt: tt)
                let physicalSource = try #require(Engine.PlanetDE441.state(of: planet, tt: tt, physicalCenter: true))
                let systemSource = try #require(Engine.PlanetDE441.state(of: planet, tt: tt, physicalCenter: false))
                let physical = try planet.heliocentricState(at: time)
                let system = try planet.systemHeliocentricState(at: time)
                let physicalPosition = SIMD3(physical.x, physical.y, physical.z)
                let physicalVelocity = SIMD3(physical.vx, physical.vy, physical.vz)
                let systemPosition = SIMD3(system.x, system.y, system.z)
                let systemVelocity = SIMD3(system.vx, system.vy, system.vz)
                #expect(Self.norm(physicalPosition - physicalSource.position) < 1e-10, "\(planet) TT \(tt)")
                #expect(Self.norm(physicalVelocity - physicalSource.velocity) < 2e-14, "\(planet) TT \(tt)")
                #expect(Self.norm(systemPosition - systemSource.position) < 1e-10, "\(planet) TT \(tt)")
                #expect(Self.norm(systemVelocity - systemSource.velocity) < 2e-14, "\(planet) TT \(tt)")
            }
        }
    }

    @Test("Every planet preserves exact blend boundaries and analytic TT derivatives")
    func selectedWindowBoundaries() throws {
        let boundaries = [-36_556.5, -36_524.5, 47_846.5, 47_878.5]
        for (boundaryIndex, tt) in boundaries.enumerated() {
            for planet in Engine.Planet.allCases {
                for epoch in [tt.nextDown, tt, tt.nextUp] {
                    let time = Self.time(tt: epoch)
                    let state = try planet.heliocentricEclipticState(at: time)
                    let weight = Engine.PlanetDE441.weight(tt: epoch).weight
                    #expect(weight >= 0 && weight <= 1, "\(planet) TT \(epoch)")
                    if weight == 0 {
                        let retained = try planet.retainedEclipticState(at: time)
                        #expect(
                            [state.x, state.y, state.z, state.vx, state.vy, state.vz].map(\.bitPattern)
                                == [retained.x, retained.y, retained.z, retained.vx, retained.vy, retained.vz].map(
                                    \.bitPattern))
                    } else {
                        _ = try #require(Engine.PlanetDE441.state(of: planet, tt: epoch, physicalCenter: true))
                    }
                }
                let h = 1.0 / 128
                func position(_ epoch: Double) throws -> SIMD3<Double> {
                    let state = try planet.heliocentricEclipticState(at: Self.time(tt: epoch))
                    return SIMD3(state.x, state.y, state.z)
                }
                let state = try planet.heliocentricEclipticState(at: Self.time(tt: tt))
                let derivative =
                    try (position(tt - 2 * h) - 8 * position(tt - h) + 8 * position(tt + h) - position(tt + 2 * h))
                    / (12 * h)
                #expect(Self.norm(SIMD3(state.vx, state.vy, state.vz) - derivative) < 2e-9, "\(planet) TT \(tt)")
            }
            let exact = Engine.PlanetDE441.weight(tt: tt)
            #expect(exact == (boundaryIndex == 0 || boundaryIndex == 3 ? (0, 0) : (1, 0)))
        }
    }

    // MARK: - Consistency

    /// Epochs on both paths: in the polynomial span, in an excluded Mercury
    /// segment, and outside the span on both sides.
    static let epochs: [(planet: Engine.Planet, tt: Double)] =
        Engine.Planet.allCases.flatMap { planet in
            [(planet, 9_496.375), (planet, -50_000.5), (planet, 1_000_000.25)]
        } + [(.mercury, Engine.PlanetPolynomial.mercury.start(ofSegment: 14) + 3)]

    @Test("A state's position is the position, and the distance is its length")
    func consistency() throws {
        for (planet, tt) in Self.epochs {
            let time = Self.time(tt: tt)
            let position = try planet.heliocentricEclipticPosition(at: time, cache: Self.cache())
            let state = try planet.heliocentricEclipticState(at: time, cache: Self.cache())
            #expect(
                [state.x, state.y, state.z].map(\.bitPattern) == [position.x, position.y, position.z].map(\.bitPattern))
            let equatorial = try planet.heliocentricPosition(at: time, cache: Self.cache())
            let rotated = Engine.VSOP87B.toEquatorial.apply(to: position)
            #expect(
                [equatorial.x, equatorial.y, equatorial.z].map(\.bitPattern)
                    == [rotated.x, rotated.y, rotated.z].map(\.bitPattern))
            let equatorialState = try planet.heliocentricState(at: time, cache: Self.cache())
            let rotatedState = Engine.VSOP87B.toEquatorial.apply(to: state)
            let equatorialBits = [
                equatorialState.x, equatorialState.y, equatorialState.z,
                equatorialState.vx, equatorialState.vy, equatorialState.vz,
            ].map(\.bitPattern)
            let rotatedBits = [
                rotatedState.x, rotatedState.y, rotatedState.z, rotatedState.vx, rotatedState.vy, rotatedState.vz,
            ].map(\.bitPattern)
            #expect(equatorialBits == rotatedBits)
            #expect(equatorial.time.tt == tt && state.time.tt == tt)
            let distance = try planet.heliocentricDistance(at: time, cache: Self.cache())
            #expect(abs(distance - position.length) <= 4e-16 * distance, "\(planet) \(tt)")
        }
    }

    // MARK: - Accepted time range

    @Test("The accepted range ends at 1,461,000 days either side of J2000")
    func rangeEnds() throws {
        for tt in [-1_461_000.0, 1_461_000.0] {
            for planet in Engine.Planet.allCases {
                let (time, cache) = (Self.time(tt: tt), Self.cache())
                _ = try planet.heliocentricPosition(at: time, cache: cache)
                _ = try planet.heliocentricState(at: time, cache: cache)
                #expect(try planet.heliocentricDistance(at: time, cache: cache) > 0)
            }
        }
    }

    @Test(
        "A TT outside the range or not finite throws badTime and leaves the cache alone",
        arguments: [(-1_461_000.0).nextDown, 1_461_000.0.nextUp, 1e300, .nan, .infinity, -.infinity])
    func outsideRange(tt: Double) {
        let time = Self.time(tt: tt)
        let cache = Self.cache()
        for planet in Engine.Planet.allCases {
            #expect(throws: AstronomyError.badTime) { try planet.heliocentricEclipticPosition(at: time, cache: cache) }
            #expect(throws: AstronomyError.badTime) { try planet.heliocentricEclipticState(at: time, cache: cache) }
            #expect(throws: AstronomyError.badTime) { try planet.heliocentricPosition(at: time, cache: cache) }
            #expect(throws: AstronomyError.badTime) { try planet.heliocentricState(at: time, cache: cache) }
            #expect(throws: AstronomyError.badTime) { try planet.heliocentricDistance(at: time, cache: cache) }
            #expect(cache.coordinates[planet.rawValue].statistics == .init())
            #expect(cache.derivatives[planet.rawValue].statistics == .init())
        }
    }

    @Test("An invalid time throws badTime")
    func invalidTime() {
        #expect(throws: AstronomyError.badTime) { try Engine.Planet.earth.heliocentricPosition(at: .invalid) }
        #expect(throws: AstronomyError.badTime) { try Engine.Planet.earth.heliocentricDistance(at: .invalid) }
    }
}

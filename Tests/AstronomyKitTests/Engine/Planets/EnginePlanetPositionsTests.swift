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

    // MARK: - IMCCE check values

    /// Rectangular position and velocity from the published longitude,
    /// latitude, radius and their rates, on the VSOP87 axes.
    static func rectangular(_ record: PublishedVSOP87.Record) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let (l, b, r) = (record.longitude, record.latitude, record.radius)
        let position = SIMD3(r * cos(b) * cos(l), r * cos(b) * sin(l), r * sin(b))
        let (dl, db, dr) = (record.longitudeRate, record.latitudeRate, record.radiusRate)
        let velocity = SIMD3(
            dr * cos(b) * cos(l) - r * sin(b) * cos(l) * db - r * cos(b) * sin(l) * dl,
            dr * cos(b) * sin(l) - r * sin(b) * sin(l) * db + r * cos(b) * cos(l) * dl,
            dr * sin(b) + r * cos(b) * db)
        return (position, velocity)
    }

    /// The printed angles and radius are each within 5e-11 of the series, and
    /// the published computation rounds longitude by up to about 3e-11 more,
    /// so a component is within about 1e-10 × (1 + 2r) AU and a velocity
    /// component within about 1e-10 × (1 + 2r) AU per day plus the rates'
    /// share of the angle error, which is far smaller. Fits add under 1e-12 AU.
    static func allowance(radius: Double) -> Double { 1e-10 * (1 + 2 * radius) }

    @Test(
        "Ecliptic position and velocity against IMCCE vsop87.chk, J2000 through the polynomials and earlier dates through the series",
        arguments: PublishedVSOP87.records)
    func publishedEcliptic(record: PublishedVSOP87.Record) throws {
        let polynomial = Engine.PlanetPolynomial.position(record.planet, tt: record.tt) != nil
        #expect(polynomial == (record.tt == 0))
        let cache = Self.cache()
        let state = try record.planet.heliocentricEclipticState(at: Self.time(tt: record.tt), cache: cache)
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

    /// 1 arcminute is the accuracy `JPLValidationTests` applies to the
    /// geocentric planets (1.5′ for Neptune). The largest angle here is 2.4″, for Neptune; VSOP87 was fitted
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
            #expect(equatorialState.vx == Engine.VSOP87B.toEquatorial.apply(to: state).vx)
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

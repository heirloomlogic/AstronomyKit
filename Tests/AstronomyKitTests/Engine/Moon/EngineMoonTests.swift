//
//  EngineMoonTests.swift
//  AstronomyKit
//
//  The lunar model's routing between DE440 and compact DE441, and the Moon's
//  positions at the edges of their inputs.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine Moon")
struct EngineMoonTests {
    typealias Ephemeris = Engine.MoonEphemeris

    /// The DE440 Moon alone at `tt`, as longitude, latitude and distance.
    static func ephemerisCoordinates(tt: Double) throws -> SIMD3<Double> {
        let p = try #require(Engine.Moon.meanEclipticPosition(tt: tt))
        var longitude = atan2(p.y, p.x)
        if longitude < 0 { longitude += 2 * .pi }
        return SIMD3(longitude, atan2(p.z, hypot(p.x, p.y)), (p.x * p.x + p.y * p.y + p.z * p.z).squareRoot())
    }

    @Test("At full weight the model is DE440 alone; beyond the blends it is DE441 alone")
    func routing() throws {
        for tt in [Ephemeris.fullWeightStart, -10_000.5, 0, 30_000.25, Ephemeris.fullWeightEnd] {
            let t = tt / 36_525
            #expect(try Engine.Moon.coordinates(centuries: t) == Self.ephemerisCoordinates(tt: t * 36_525))
        }
        for tt in [
            Ephemeris.fullWeightStart - Ephemeris.blendDays, -1_000_000, Ephemeris.fullWeightEnd + Ephemeris.blendDays,
            1_000_000,
        ] {
            let t = tt / 36_525
            #expect(
                EngineMoonEphemerisTests.largest(
                    Engine.Moon.rectangular(Engine.Moon.coordinates(centuries: t))
                        - (try #require(Engine.Moon.meanEclipticPosition(tt: t * 36_525, compact: true)))) < 1e-17)
        }
    }

    @Test("In a blend the position lies between DE441 and DE440 at the weight's fraction")
    func blend() throws {
        for tt in [
            Ephemeris.fullWeightStart - 24, Ephemeris.fullWeightStart - 3.5, Ephemeris.fullWeightEnd + 1.25,
            Ephemeris.fullWeightEnd + 16,
        ] {
            let t = tt / 36_525
            let weight = Ephemeris.weight(tt: t * 36_525).weight
            #expect(weight > 0 && weight < 1)
            let blended = Engine.Moon.rectangular(Engine.Moon.coordinates(centuries: t))
            let series = try #require(Engine.Moon.meanEclipticPosition(tt: t * 36_525, compact: true))
            let ephemeris = Engine.Moon.rectangular(try Self.ephemerisCoordinates(tt: t * 36_525))
            let expected = series + weight * (ephemeris - series)
            let error = EngineMoonEphemerisTests.largest(blended - expected)
            #expect(error <= 1e-17, "tt \(tt)")
        }
    }

    @Test("The model has no jump at the blends' ends")
    func blendEnds() {
        for tt in [
            Ephemeris.fullWeightStart - Ephemeris.blendDays, Ephemeris.fullWeightStart,
            Ephemeris.fullWeightEnd, Ephemeris.fullWeightEnd + Ephemeris.blendDays,
        ] {
            let below = Engine.Moon.rectangular(Engine.Moon.coordinates(centuries: (tt - 1e-7) / 36_525))
            let above = Engine.Moon.rectangular(Engine.Moon.coordinates(centuries: (tt + 1e-7) / 36_525))
            // The Moon moves under 1.4e-10 AU in 2e-7 day; a jump would be
            // the series' error, about 1e-7 AU.
            let step = EngineMoonEphemerisTests.largest(above - below)
            #expect(step < 2e-10, "tt \(tt): \(step) AU")
        }
    }

    @Test("Longitudes stay from 0 to 2π, and in [0, 360) on the true ecliptic, across the wrap")
    func longitudeRange() throws {
        var wrapped = 0
        var previous = 0.0
        for step in 0..<2_000 {
            let tt = -40_000 + Double(step) * 0.75
            let longitude = Engine.Moon.coordinates(centuries: tt / 36_525).x
            #expect(longitude >= 0 && longitude <= 2 * .pi, "tt \(tt)")
            let ecliptic = try Engine.Moon.eclipticPosition(at: PlanetTestSupport.time(tt: tt)).longitude
            #expect(ecliptic >= 0 && ecliptic < 360, "tt \(tt)")
            if longitude < previous { wrapped += 1 }
            previous = longitude
        }
        // 1,500 days cross 0 about 55 times.
        #expect(wrapped >= 50)
    }

    @Test("The ecliptic position is the J2000 position seen on the true ecliptic of date, with the model's distance")
    func eclipticMatchesEquatorial() throws {
        for tt in [-1_000_000.0, -36_540.0, 0, 9_497.375, 47_860.0, 700_000.0] {
            let time = PlanetTestSupport.time(tt: tt)
            let ecliptic = try Engine.Moon.eclipticPosition(at: time)
            let fromEquator = Engine.Ecliptic(try Engine.Moon.geocentricPosition(at: time))
            #expect(abs(remainder(ecliptic.longitude - fromEquator.longitude, 360)) <= 1e-12, "tt \(tt)")
            #expect(abs(ecliptic.latitude - fromEquator.latitude) <= 1e-12, "tt \(tt)")
            #expect(ecliptic.distance == Engine.Moon.coordinates(centuries: tt / 36_525).z)
            let length = try Engine.Moon.geocentricPosition(at: time).length
            #expect(abs(ecliptic.distance - length) <= 1e-17, "tt \(tt)")
        }
    }

    @Test("The accepted range's ends are accepted and the doubles beyond are not")
    func acceptedRange() throws {
        let limit = Engine.acceptedTTDays
        for tt in [-limit, limit] {
            _ = try Engine.Moon.geocentricPosition(at: PlanetTestSupport.time(tt: tt))
            _ = try Engine.Moon.eclipticPosition(at: PlanetTestSupport.time(tt: tt))
        }
        for tt in [(-limit).nextDown, limit.nextUp] {
            let time = PlanetTestSupport.time(tt: tt)
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.geocentricPosition(at: time) }
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.eclipticPosition(at: time) }
        }
    }

    @Test("A time that is not finite is rejected", arguments: [Double.nan, .infinity, -.infinity])
    func notFinite(tt: Double) {
        let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
        #expect(throws: AstronomyError.badTime) { try Engine.Moon.geocentricPosition(at: time) }
        #expect(throws: AstronomyError.badTime) { try Engine.Moon.eclipticPosition(at: time) }
        #expect(throws: AstronomyError.badTime) { try Engine.Moon.geocentricPosition(at: .invalid) }
        let coordinates = Engine.Moon.coordinates(centuries: tt)
        #expect(coordinates.x.isNaN && coordinates.y.isNaN && coordinates.z.isNaN)
    }

    @Test("The series' distance comes from the parallax with the published au")
    func seriesDistance() {
        #expect(Engine.LunarSeries.earthEquatorialRadius == 6_378.1366 / 149_597_870.7)
        #expect(Engine.LunarSeries.arc == 648_000 / Double.pi)
    }
}

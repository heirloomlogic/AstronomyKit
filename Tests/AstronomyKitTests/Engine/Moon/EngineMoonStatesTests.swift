//
//  EngineMoonStatesTests.swift
//  AstronomyKit
//
//  The Moon's states and the Earth-Moon barycenter against JPL Horizons,
//  and their rates against differences of the same positions.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine Moon states")
struct EngineMoonStatesTests {
    typealias Ephemeris = Engine.MoonEphemeris

    static func time(tt: Double) -> Engine.Time { PlanetTestSupport.time(tt: tt) }

    /// TT instants on binary fractions of a day in each part of the model:
    /// the series before and after DE440, both blends, and DE440 alone.
    static let instants: [Double] = [
        -1_000_000.25, -200_000.5, -36_540.0, -36_531.75, -36_524.5, -12_345.625, 0, 9_497.375, 47_846.5,
        47_850.125, 47_870.0, 200_000.25, 1_000_000.75,
    ]

    // MARK: - Published states

    /// Horizons' Moon and Earth-Moon barycenter states from Earth's center,
    /// every 8 days from 1970 to 2040, from Astronomy Engine's
    /// `barystate/GeoMoon.txt` and `GeoEMB.txt` at the pinned revision.
    static let published = IndependentReferenceArchive.shared.geocentricStates

    /// The relative error of `actual` against `expected`, as Astronomy
    /// Engine's `StateVectorDiff` measures it.
    static func relativeError(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>) -> Double {
        let difference = actual - expected
        return ((difference * difference).sum() / (expected * expected).sum()).squareRoot()
    }

    @Test("Moon and barycenter states within Astronomy Engine's relative limits for 1970 to 2040")
    func againstHorizons() throws {
        #expect(Self.published.count == 6_392)
        var bodies = Set<String>()
        for reference in Self.published {
            let tdb = reference.julianDateTDB - 2_451_545
            let time = Self.time(tt: tdb - Engine.TDB.offsetSeconds(tt: tdb) / Engine.secondsPerDay)
            let state =
                reference.body == "moon"
                ? try Engine.Moon.geocentricState(at: time) : try Engine.Moon.barycenterState(at: time)
            let position = Self.relativeError(Self.position(state), Self.eqj(reference.positionAU))
            let velocity = Self.relativeError(Self.velocity(state), Self.eqj(reference.velocityAUPerDay))
            #expect(position <= reference.relativePositionTolerance, "\(reference.body) JD \(reference.julianDateTDB)")
            #expect(velocity <= reference.relativeVelocityTolerance, "\(reference.body) JD \(reference.julianDateTDB)")
            bodies.insert(reference.body)
        }
        #expect(bodies == ["moon", "emb"])
    }

    /// A Horizons vector on ICRF axes rotated to the engine's EQJ.
    static func eqj(_ icrf: [Double]) -> SIMD3<Double> {
        Engine.FrameBias.icrsToEqj.apply(to: SIMD3(icrf[0], icrf[1], icrf[2]))
    }

    static func position<F>(_ state: Engine.State<F>) -> SIMD3<Double> { SIMD3(state.x, state.y, state.z) }

    static func velocity<F>(_ state: Engine.State<F>) -> SIMD3<Double> { SIMD3(state.vx, state.vy, state.vz) }

    @Test("The checks fail for the barycenter given as the Moon, or a day off")
    func negativeControls() throws {
        let reference = try #require(Self.published.first { $0.body == "moon" })
        let tdb = reference.julianDateTDB - 2_451_545
        let expected = Self.eqj(reference.positionAU)
        let barycenter = try Engine.Moon.barycenterState(at: Self.time(tt: tdb))
        #expect(Self.relativeError(Self.position(barycenter), expected) > reference.relativePositionTolerance)
        let late = try Engine.Moon.geocentricState(at: Self.time(tt: tdb + 1))
        #expect(Self.relativeError(Self.position(late), expected) > reference.relativePositionTolerance)
    }

    // MARK: - Identities

    @Test("A state's position is the position, and the barycenter is the Moon scaled, double for double")
    func identities() throws {
        for tt in Self.instants {
            let time = Self.time(tt: tt)
            let position = try Engine.Moon.geocentricPosition(at: time)
            let state = try Engine.Moon.geocentricState(at: time)
            #expect([state.x, state.y, state.z] == [position.x, position.y, position.z], "tt \(tt)")
            let barycenter = try Engine.Moon.barycenterState(at: time)
            let d = 1 + Engine.Moon.earthMoonMassRatio
            #expect(
                [barycenter.x, barycenter.y, barycenter.z, barycenter.vx, barycenter.vy, barycenter.vz]
                    == [state.x / d, state.y / d, state.z / d, state.vx / d, state.vy / d, state.vz / d],
                "tt \(tt)")
            let sphere = try Engine.Moon.eclipticPosition(at: time)
            let ecliptic = try Engine.Moon.eclipticState(at: time)
            #expect(
                [ecliptic.longitude, ecliptic.latitude, ecliptic.distance]
                    == [sphere.longitude, sphere.latitude, sphere.distance], "tt \(tt)")
            #expect(state.time.ut == time.ut && ecliptic.state.time.ut == time.ut)
        }
    }

    // MARK: - Rates

    /// A five-point difference on a 1/64-day stencil, whose own truncation
    /// is below 1e-11 of the speed.
    static let step = 1.0 / 64

    /// The allowed relative difference at `tt`. In the series the velocity
    /// is a central difference over ±5e-4 day. Its truncation is about
    /// (5e-4)²/6 · ω² ≈ 2e-9 of the speed for the Moon's ω ≈ 0.23 rad/day,
    /// and the series rounds arguments that grow by 2π · 1,337 rad per
    /// Julian century, which over that difference comes to about 4e-9 of
    /// the speed per century from J2000. The allowance is 1e-8 for each, so
    /// it grows with |t| in centuries.
    static func allowance(tt: Double) -> Double {
        1e-8 * (1 + abs(tt) / 36_525)
    }

    @Test("The EQJ velocity is the derivative of the position", arguments: instants)
    func velocity(tt: Double) throws {
        let velocity = try Self.velocity(Engine.Moon.geocentricState(at: Self.time(tt: tt)))
        // PublishedOrientation.derivative's stencil, on all three components at once.
        let p = { (k: Double) throws -> SIMD3<Double> in
            let vector = try Engine.Moon.geocentricPosition(at: Self.time(tt: tt + k * Self.step))
            return SIMD3(vector.x, vector.y, vector.z)
        }
        let difference = try (p(-2) - 8 * p(-1) + 8 * p(1) - p(2)) / (12 * Self.step)
        let speed = (velocity * velocity).sum().squareRoot()
        let error = EngineMoonEphemerisTests.largest(velocity - difference)
        #expect(error <= Self.allowance(tt: tt) * speed, "tt \(tt): \(error / speed) of the speed")
    }

    @Test("The ecliptic rates are the derivatives of the ecliptic position", arguments: instants)
    func eclipticRates(tt: Double) throws {
        let state = try Engine.Moon.eclipticState(at: Self.time(tt: tt))
        func derivative(_ field: @escaping (Engine.Spherical) -> Double) -> Double {
            PublishedOrientation.derivative(at: tt, step: Self.step) { t in
                (try? field(Engine.Moon.eclipticPosition(at: Self.time(tt: t)))) ?? .nan
            }
        }
        // Unwrap longitude around the center value.
        let longitude = derivative { remainder($0.longitude - state.longitude, 360) }
        let latitude = derivative(\.latitude)
        let distance = derivative(\.distance)
        // Scaled by the Moon's largest motion: about 15°/day, and 6e-4 AU/day.
        let allowance = Self.allowance(tt: tt)
        #expect(abs(state.longitudeRate - longitude) <= allowance * 15, "tt \(tt)")
        #expect(abs(state.latitudeRate - latitude) <= allowance * 15, "tt \(tt)")
        #expect(abs(state.distanceRate - distance) <= allowance * 6e-4, "tt \(tt)")
    }

    /// The velocity test above would catch a blend that left out the
    /// weight's rate: mid-blend the weight changes by about 0.06 a day and
    /// the two models are a few km apart, a term of a few millionths of the
    /// speed against that test's 1e-8.
    @Test("The weight's rate times the models' separation is large enough for the velocity test to see")
    func blendRateMatters() throws {
        let tt = Ephemeris.fullWeightStart - Ephemeris.blendDays / 2
        let (weight, rate) = Ephemeris.weight(tt: tt)
        #expect(weight == 0.5 && rate > 0.04)
        let source = try #require(Engine.Moon.meanEclipticSourceState(tt: tt))
        let legacy = Engine.Moon.rectangular(Engine.LunarSeries.coordinates(centuries: tt / 36_525))
        let term = rate * (source.position - legacy)
        let speed = (source.velocity * source.velocity).sum().squareRoot()
        #expect(EngineMoonEphemerisTests.largest(term) > 1e-6 * speed)
    }

    // MARK: - Edges

    @Test("The accepted range's ends are accepted and the doubles beyond are not")
    func acceptedRange() throws {
        let limit = Engine.acceptedTTDays
        for tt in [-limit, limit] {
            _ = try Engine.Moon.geocentricState(at: Self.time(tt: tt))
            _ = try Engine.Moon.barycenterState(at: Self.time(tt: tt))
            _ = try Engine.Moon.eclipticState(at: Self.time(tt: tt))
        }
        for tt in [(-limit).nextDown, limit.nextUp, .nan, .infinity, -.infinity] {
            let time = Self.time(tt: tt)
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.geocentricState(at: time) }
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.barycenterState(at: time) }
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.eclipticState(at: time) }
        }
    }
}

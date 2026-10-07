//
//  EnginePositionsTests.swift
//  AstronomyKit
//
//  Heliocentric, barycentric, backdated and geocentric positions: routing
//  to each body's model, the identities between positions and states, the
//  order of errors, the accepted range, velocities against differenced
//  positions, the light-time solution and the aberration approximation.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Positions")
struct EnginePositionsTests {
    typealias Positions = Engine.Positions

    static let planets: [CelestialBody] = [
        .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune,
    ]

    /// Every body the functions cover.
    static let supported: [CelestialBody] =
        [.sun] + planets + [.pluto, .moon, .earthMoonBarycenter, .solarSystemBarycenter]

    static let unsupported: [CelestialBody] = [.io, .europa, .ganymede, .callisto]

    /// TT instants: 1800 and 2200, where the planets come from the full
    /// series and the Moon from the lunar series, and 1945, 2000 and 2026,
    /// inside the polynomial fits and the DE440 Moon and Pluto. Each is a
    /// multiple of 1/64 day, so the difference stencils below are exact, and
    /// none is within 2/64 day of a polynomial segment boundary.
    static let instants: [Double] = [-73_010.25, -20_000.5, 0.25, 9_500.75, 73_010.125]

    /// The bodies to evaluate at `tt`. Pluto only inside the DE440 span: its
    /// integrated model takes seconds a segment in Debug and is checked by
    /// `PlutoSegmentSuites`, which reads the segments one test at a time.
    static func bodies(at tt: Double) -> [CelestialBody] {
        supported.filter { $0 != .pluto || Engine.MoonEphemeris.weight(tt: tt).weight == 1 }
    }

    static func time(tt: Double) -> Engine.Time { Engine.Time(tt: tt, deltaTModel: .espenakMeeus) }

    static func simd(_ vector: Engine.Vector<Engine.EQJ>) -> SIMD3<Double> {
        SIMD3(vector.x, vector.y, vector.z)
    }

    static func length(_ v: SIMD3<Double>) -> Double { EngineGravityTests.length(v) }

    // MARK: - Routing

    @Test("Heliocentric positions come from each body's model", arguments: instants)
    func heliocentricRouting(tt: Double) throws {
        let time = Self.time(tt: tt)
        let earth = Self.simd(try Engine.Planet.earth.heliocentricPosition(at: time))
        let moon = Self.simd(try Engine.Moon.geocentricPosition(at: time))
        for body in Self.bodies(at: tt) {
            let position = try Positions.heliocentricPosition(of: body, at: time)
            #expect(position.time.tt == tt && position.time.ut == time.ut, "\(body)")
            let expected: SIMD3<Double>
            switch body {
            case .sun: expected = .zero
            case .pluto: expected = Self.simd(try Engine.Pluto.heliocentricPosition(at: time))
            case .moon: expected = moon + earth
            case .earthMoonBarycenter: expected = earth + moon / (1 + Engine.Moon.earthMoonMassRatio)
            case .solarSystemBarycenter: expected = -(try Engine.Gravity.MajorBodies(tt: tt).sun.position)
            default:
                expected = Self.simd(try #require(Engine.Planet(body)).heliocentricPosition(at: time))
            }
            #expect(Self.simd(position) == expected, "\(body) at \(tt)")
        }
    }

    @Test(
        "A heliocentric state's position is the heliocentric position, double for double",
        arguments: instants)
    func heliocentricStateIdentity(tt: Double) throws {
        let time = Self.time(tt: tt)
        for body in Self.bodies(at: tt) {
            let state = try Positions.heliocentricState(of: body, at: time)
            let position = try Positions.heliocentricPosition(of: body, at: time)
            #expect(state.positionVector == Self.simd(position), "\(body) at \(tt)")
            #expect(state.time.tt == tt, "\(body)")
        }
        let sun = try Positions.heliocentricState(of: .sun, at: time)
        #expect(sun.positionVector == .zero && sun.velocityVector == .zero)
        let barycenter = try Positions.heliocentricState(of: .solarSystemBarycenter, at: time)
        let barycentricSun = try Positions.barycentricState(of: .sun, at: time)
        #expect(barycenter.positionVector == -barycentricSun.positionVector)
        #expect(barycenter.velocityVector == -barycentricSun.velocityVector)
    }

    /// The Sun and the planets add the Sun's barycentric state to their
    /// heliocentric one with the same operands, so they match exactly. The
    /// Moon, the Earth-Moon barycenter and Pluto group the sum differently
    /// and match to rounding.
    @Test(
        "Barycentric states are the Sun's barycentric state plus the heliocentric ones",
        arguments: instants)
    func barycentricComposition(tt: Double) throws {
        let time = Self.time(tt: tt)
        let sun = try Positions.barycentricState(of: .sun, at: time)
        for body in Self.bodies(at: tt) where body != .solarSystemBarycenter {
            let barycentric = try Positions.barycentricState(of: body, at: time)
            let heliocentric = try Positions.heliocentricState(of: body, at: time)
            let position = heliocentric.positionVector + sun.positionVector
            let velocity = heliocentric.velocityVector + sun.velocityVector
            #expect(barycentric.time.tt == tt, "\(body)")
            if [.moon, .earthMoonBarycenter, .pluto].contains(body) {
                #expect(Self.length(barycentric.positionVector - position) <= 1e-14, "\(body) at \(tt)")
                #expect(Self.length(barycentric.velocityVector - velocity) <= 1e-17, "\(body) at \(tt)")
            } else {
                #expect(barycentric.positionVector == position, "\(body) at \(tt)")
                #expect(barycentric.velocityVector == velocity, "\(body) at \(tt)")
            }
        }
        let barycenter = try Positions.barycentricState(of: .solarSystemBarycenter, at: time)
        #expect(barycenter.positionVector == .zero && barycenter.velocityVector == .zero)
    }

    @Test(
        "Heliocentric distance is the planet's distance or the position's length", arguments: instants)
    func heliocentricDistance(tt: Double) throws {
        let time = Self.time(tt: tt)
        for body in Self.bodies(at: tt) {
            let distance = try Positions.heliocentricDistance(of: body, at: time)
            if let planet = Engine.Planet(body) {
                #expect(distance == (try planet.heliocentricDistance(at: time)), "\(body)")
            } else {
                #expect(
                    distance == (try Positions.heliocentricPosition(of: body, at: time).length), "\(body)")
            }
        }
        #expect(try Positions.heliocentricDistance(of: .sun, at: Self.time(tt: 0)) == 0)
    }

    // MARK: - Errors and the accepted range

    @Test("Bodies no model covers throw invalidBody, after the time check")
    func unsupportedBodies() throws {
        let time = Self.time(tt: 0)
        let outside = Self.time(tt: Engine.acceptedTTDays + 1)
        for body in Self.unsupported {
            for (at, error) in [(time, AstronomyError.invalidBody), (outside, .badTime)] {
                #expect(throws: error) { try Positions.heliocentricPosition(of: body, at: at) }
                #expect(throws: error) { try Positions.heliocentricState(of: body, at: at) }
                #expect(throws: error) { try Positions.heliocentricDistance(of: body, at: at) }
                #expect(throws: error) { try Positions.barycentricState(of: body, at: at) }
                for aberration in [Aberration.none, .corrected] {
                    #expect(throws: error) {
                        try Positions.geocentricPosition(of: body, at: at, aberration: aberration)
                    }
                    #expect(throws: error) {
                        try Positions.backdatedPosition(
                            of: body, seenFrom: .earth, at: at, aberration: aberration)
                    }
                    #expect(throws: error) {
                        try Positions.backdatedPosition(
                            of: .mars, seenFrom: body, at: at, aberration: aberration)
                    }
                }
            }
        }
    }

    /// Every function at each end of the accepted range, beyond it, and for
    /// times that are not finite. Pluto's own range is narrower.
    @Test("The accepted range bounds every evaluated time, backdated ones included")
    func acceptedRange() throws {
        let bodies = Self.supported.filter { $0 != .pluto }
        for end in [-Engine.acceptedTTDays, Engine.acceptedTTDays] {
            let time = PlanetTestSupport.time(tt: end)
            for body in bodies {
                _ = try Positions.heliocentricPosition(of: body, at: time)
                _ = try Positions.heliocentricState(of: body, at: time)
                _ = try Positions.heliocentricDistance(of: body, at: time)
                _ = try Positions.barycentricState(of: body, at: time)
            }
            #expect(throws: AstronomyError.badTime) {
                try Positions.heliocentricPosition(of: .pluto, at: time)
            }
            #expect(throws: AstronomyError.badTime) {
                try Positions.barycentricState(of: .pluto, at: time)
            }
        }
        let beyond =
            [
                Engine.acceptedTTDays.nextUp, -Engine.acceptedTTDays.nextUp, .nan, .infinity, -.infinity,
            ].map(PlanetTestSupport.time(tt:)) + [.invalid]
        for time in beyond {
            for body in Self.supported {
                #expect(throws: AstronomyError.badTime) {
                    try Positions.heliocentricPosition(of: body, at: time)
                }
                #expect(throws: AstronomyError.badTime) {
                    try Positions.heliocentricState(of: body, at: time)
                }
                #expect(throws: AstronomyError.badTime) {
                    try Positions.heliocentricDistance(of: body, at: time)
                }
                #expect(throws: AstronomyError.badTime) {
                    try Positions.barycentricState(of: body, at: time)
                }
                #expect(throws: AstronomyError.badTime) {
                    try Positions.geocentricPosition(of: body, at: time, aberration: .corrected)
                }
            }
        }

        // At the late end the light-time backdates stay inside the range. At
        // the early end they leave it, except for Earth and the Moon, which
        // are not backdated.
        let late = Self.time(tt: Engine.acceptedTTDays)
        let early = Self.time(tt: -Engine.acceptedTTDays)
        for body in bodies {
            for aberration in [Aberration.none, .corrected] {
                _ = try Positions.geocentricPosition(of: body, at: late, aberration: aberration)
                if body == .earth || body == .moon {
                    _ = try Positions.geocentricPosition(of: body, at: early, aberration: aberration)
                } else {
                    #expect(throws: AstronomyError.badTime, "\(body)") {
                        try Positions.geocentricPosition(of: body, at: early, aberration: aberration)
                    }
                }
            }
        }
    }

    // MARK: - Velocities

    /// `f′(tt)` from the five-point stencil on 1/64-day steps.
    static func derivative(
        at tt: Double, _ f: (Double) throws -> SIMD3<Double>
    ) rethrows -> SIMD3<
        Double
    > {
        let h = 1.0 / 64
        let terms = try (f(tt - 2 * h) - f(tt + 2 * h)) + 8 * (f(tt + h) - f(tt - h))
        return terms / (12 * h)
    }

    /// The velocity allowance for `body` at `tt`, in AU per day.
    ///
    /// The planets, Pluto's DE440 tables and the DE440 Moon have analytic
    /// velocities. The stencil differences positions whose series arguments
    /// round in proportion to the time from J2000, so the allowance is
    /// (1 + |t|) · 1e-11, t in Julian centuries: measured, the largest error
    /// is 5e-13 inside the polynomial fits and 1.4e-11 (Mercury) at t = 2.
    /// Where the Moon comes from the lunar series its velocity is a central
    /// difference over ±5e-4 day, and the Moon's suites allow
    /// (1 + |t|) · 1e-8 of its largest speed relative to Earth, 6e-4 AU per
    /// day, on top.
    static func velocityAllowance(_ body: CelestialBody, tt: Double) -> Double {
        let scale = 1 + abs(tt) / 36_525
        let lunarSeries = Engine.MoonEphemeris.weight(tt: tt).weight < 1
        let lunar = lunarSeries && (body == .moon || body == .earthMoonBarycenter) ? 1e-8 * 6e-4 : 0
        return scale * (1e-11 + lunar)
    }

    /// Every body's heliocentric velocity, and the barycentric velocity of
    /// the bodies whose barycentric state is not the Sun's plus the
    /// heliocentric one exactly (see `barycentricComposition`): the Sun
    /// itself, the Moon, the Earth-Moon barycenter and Pluto.
    @Test(
        "Heliocentric and barycentric velocities are the derivatives of the positions",
        arguments: instants)
    func velocities(tt: Double) throws {
        for body in Self.bodies(at: tt) {
            let allowance = Self.velocityAllowance(body, tt: tt)
            let heliocentric = try Positions.heliocentricState(of: body, at: Self.time(tt: tt))
            let heliocentricRate = try Self.derivative(at: tt) {
                try Positions.heliocentricState(of: body, at: Self.time(tt: $0)).positionVector
            }
            let heliocentricError = Self.length(heliocentric.velocityVector - heliocentricRate)
            #expect(heliocentricError <= allowance, "\(body) at \(tt): heliocentric \(heliocentricError)")
            guard [.sun, .moon, .earthMoonBarycenter, .pluto].contains(body) else { continue }
            let barycentric = try Positions.barycentricState(of: body, at: Self.time(tt: tt))
            let barycentricRate = try Self.derivative(at: tt) {
                try Positions.barycentricState(of: body, at: Self.time(tt: $0)).positionVector
            }
            let barycentricError = Self.length(barycentric.velocityVector - barycentricRate)
            #expect(barycentricError <= allowance, "\(body) at \(tt): barycentric \(barycentricError)")
        }
    }

    // MARK: - Light time and geocentric positions

    @Test(
        "Geocentric positions: Earth at the origin, the Moon unbackdated, other bodies backdated",
        arguments: instants)
    func geocentricRouting(tt: Double) throws {
        let time = Self.time(tt: tt)
        for body in Self.bodies(at: tt) {
            for aberration in [Aberration.none, .corrected] {
                let vector = try Positions.geocentricPosition(of: body, at: time, aberration: aberration)
                #expect(vector.time.tt == time.tt && vector.time.ut == time.ut, "\(body)")
                let expected: SIMD3<Double>
                switch body {
                case .earth: expected = .zero
                case .moon: expected = Self.simd(try Engine.Moon.geocentricPosition(at: time))
                default:
                    expected = Self.simd(
                        try Positions.backdatedPosition(
                            of: body, seenFrom: .earth, at: time, aberration: aberration))
                }
                #expect(Self.simd(vector) == expected, "\(body) \(aberration) at \(tt)")
            }
        }
    }

    /// The vector is the target at the backdated time less the observer at
    /// the observation time (`.none`) or the backdated time (`.corrected`),
    /// with the same operations, and the backdated time is the observation
    /// time less the vector's light time, to the iteration's 1e-9 day.
    @Test("Backdating solves the light-time equation", arguments: [Aberration.none, .corrected])
    func lightTime(aberration: Aberration) throws {
        let pairs: [(target: CelestialBody, observer: CelestialBody)] = [
            (.sun, .earth), (.mercury, .earth), (.mars, .earth), (.jupiter, .earth), (.neptune, .earth),
            (.pluto, .earth), (.moon, .earth), (.earthMoonBarycenter, .earth),
            (.solarSystemBarycenter, .earth),
            (.jupiter, .saturn), (.earth, .mars), (.venus, .sun),
        ]
        let time = Self.time(tt: 9_500.75)
        for (target, observer) in pairs {
            let vector = try Positions.backdatedPosition(
                of: target, seenFrom: observer, at: time, aberration: aberration)
            let lightTime = vector.length / Engine.speedOfLightAUPerDay
            #expect(
                abs(vector.time.tt - time.adding(days: -lightTime).tt) < 1e-9, "\(target) from \(observer)")
            #expect(vector.time.deltaTModel == time.deltaTModel)
            let position = Self.simd(try Positions.heliocentricPosition(of: target, at: vector.time))
            let origin = Self.simd(
                try Positions.heliocentricPosition(
                    of: observer, at: aberration == .none ? time : vector.time))
            #expect(Self.simd(vector) == position - origin, "\(target) from \(observer)")
        }

        let same = try Positions.backdatedPosition(
            of: .mars, seenFrom: .mars, at: time, aberration: aberration)
        #expect(Self.simd(same) == .zero && same.time.tt == time.tt)
    }

    /// Backdating the observer with the target shifts the direction by the
    /// observer's velocity across the line of sight over the speed of light,
    /// the first-order (Bradley) aberration. The observer moves along the
    /// chord from its backdated position to its present one, which is
    /// parallel to its velocity halfway through the light time to second
    /// order, so that is the velocity used here: at the present time instead,
    /// Earth's acceleration over Neptune's light time turns it by 0.03″. The
    /// target's own motion over the light time's change adds at most
    /// v·v⊕/c², 0.0016″ for Mars.
    ///
    /// For the Sun the shift is Earth's transverse speed over c, which over a
    /// Keplerian orbit runs from κ(1 − e) to κ(1 + e), with κ = 20.49552″
    /// the IAU constant of aberration (IAU 1976 System of Astronomical
    /// Constants, kept in the IAU 2009 system) and e = 0.0167 Earth's orbital
    /// eccentricity.
    @Test("The aberration approximation is the first-order annual aberration")
    func aberration() throws {
        let kappa = 20.49552
        let eccentricity = 0.0167
        var sunShifts: [Double] = []
        for day in stride(from: 9_131.25, to: 9_131.25 + 365, by: 7) {
            let time = Self.time(tt: day)
            for body: CelestialBody in [.sun, .mars, .jupiter, .saturn, .neptune] {
                let corrected = try Positions.geocentricPosition(of: body, at: time, aberration: .corrected)
                let uncorrected = try Positions.geocentricPosition(of: body, at: time, aberration: .none)
                let arcseconds = try corrected.angle(to: uncorrected) * 3_600
                let lightTime = uncorrected.length / Engine.speedOfLightAUPerDay
                let earth = try Positions.heliocentricState(
                    of: .earth, at: time.adding(days: -lightTime / 2))
                let direction = Self.simd(uncorrected) / uncorrected.length
                let velocity = earth.velocityVector
                let transverse = Self.length(velocity - (velocity * direction).sum() * direction)
                let expected = transverse / Engine.speedOfLightAUPerDay * Engine.degreesPerRadian * 3_600
                #expect(
                    abs(arcseconds - expected) <= 1e-3 * expected + 0.002,
                    "\(body) at \(day): \(arcseconds)″ vs \(expected)″")
                if body == .sun { sunShifts.append(arcseconds) }
            }
            let moon = try Positions.geocentricPosition(of: .moon, at: time, aberration: .corrected)
            let uncorrectedMoon = try Positions.geocentricPosition(of: .moon, at: time, aberration: .none)
            #expect(Self.simd(moon) == Self.simd(uncorrectedMoon))
        }
        let (least, most) = (try #require(sunShifts.min()), try #require(sunShifts.max()))
        #expect(least >= kappa * (1 - eccentricity) - 0.02 && most <= kappa * (1 + eccentricity) + 0.02)
        #expect(most - least >= kappa * 2 * eccentricity * 0.95, "\(least)″ to \(most)″")
    }
}

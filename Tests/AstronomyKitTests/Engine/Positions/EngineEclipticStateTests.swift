//
//  EngineEclipticStateTests.swift
//  AstronomyKit
//
//  Geocentric and ecliptic states: their positions against the position
//  functions bit for bit, their rates against differenced positions across
//  light-time switches, seams, blends and wraps, stations, and the errors
//  and accepted range.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine ecliptic states")
struct EngineEclipticStateTests {
    typealias Positions = Engine.Positions

    /// The bodies the states cover.
    static let bodies: [CelestialBody] = [
        .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
    ]

    static func time(tt: Double) -> Engine.Time { Engine.Time(tt: tt, deltaTModel: .espenakMeeus) }

    /// Evenly spaced TT instants from `start` to `end`, snapped to multiples
    /// of 1/1024 day so the stencils below are exact in binary.
    static func grid(count: Int, from start: Double = -36_000, to end: Double = 36_500) -> [Double] {
        (0..<count).map { index in
            let value = start + (end - start) * (Double(index) + 0.5) / Double(count)
            return (value * 1_024).rounded() / 1_024
        }
    }

    /// Instants beyond the polynomial fits, where the planets come from the
    /// series and the Moon from the lunar series. Pluto is left out there:
    /// its integrated model is checked by `PlutoSegmentSuites`.
    static let far: [Double] = [-55_000, -40_000, 40_000, 55_000]

    static func bodies(at tt: Double) -> [CelestialBody] {
        bodies.filter { $0 != .pluto || Engine.MoonEphemeris.weight(tt: tt).weight == 1 }
    }

    /// `f′(tt)` from the five-point stencil with step `h`.
    static func fivePoint(_ f: (Double) throws -> Double, at tt: Double, step h: Double = 1.0 / 64) rethrows -> Double {
        let terms = try (f(tt - 2 * h) - f(tt + 2 * h)) + 8 * (f(tt + h) - f(tt - h))
        return terms / (12 * h)
    }

    /// `degrees` moved by whole turns to within 180 of `reference`.
    static func unwrap(_ degrees: Double, near reference: Double) -> Double {
        reference + (degrees - reference).remainder(dividingBy: 360)
    }

    static func ecliptic(_ body: CelestialBody, tt: Double, _ aberration: Aberration) throws -> Engine.Ecliptic {
        Engine.Ecliptic(try Positions.geocentricPosition(of: body, at: time(tt: tt), aberration: aberration))
    }

    // MARK: - Positions bit for bit

    @Test(
        "The ecliptic state's position is the geocentric position on the ecliptic of date, bit for bit",
        arguments: [Aberration.corrected, .none])
    func geocentricIdentity(aberration: Aberration) throws {
        for tt in Self.grid(count: 120) + Self.far {
            let time = Self.time(tt: tt)
            for body in Self.bodies(at: tt) {
                let position = try Positions.geocentricPosition(of: body, at: time, aberration: aberration)
                let state = try Positions.geocentricState(of: body, at: time, aberration: aberration)
                #expect(state.positionVector == SIMD3(position.x, position.y, position.z), "\(body) at \(tt)")
                #expect(state.time.tt == tt && state.time.ut == time.ut)

                let expected = Engine.Ecliptic(position)
                let ecliptic = try Positions.geocentricEclipticState(of: body, at: time, aberration: aberration)
                #expect(ecliptic.state.positionVector == SIMD3(expected.vector.x, expected.vector.y, expected.vector.z))
                #expect(ecliptic.longitude.bitPattern == expected.longitude.bitPattern, "\(body) at \(tt)")
                #expect(ecliptic.latitude.bitPattern == expected.latitude.bitPattern, "\(body) at \(tt)")
                #expect(ecliptic.distance.bitPattern == expected.vector.length.bitPattern, "\(body) at \(tt)")
                #expect(ecliptic.state.time.tt == tt)
            }
        }
    }

    @Test("The Sun's ecliptic state is its ecliptic position, bit for bit")
    func sunIdentity() throws {
        for tt in Self.grid(count: 200) + Self.far {
            let time = Self.time(tt: tt)
            let position = try Positions.sunPosition(at: time)
            let state = try Positions.sunEclipticState(at: time)
            let vector = SIMD3(position.vector.x, position.vector.y, position.vector.z)
            #expect(state.state.positionVector == vector, "\(tt)")
            #expect(state.longitude.bitPattern == position.longitude.bitPattern, "\(tt)")
            #expect(state.latitude.bitPattern == position.latitude.bitPattern, "\(tt)")
            #expect(state.distance.bitPattern == position.vector.length.bitPattern, "\(tt)")
            #expect(position.vector.time.tt == tt && state.state.time.tt == tt)
        }
    }

    /// The Sun's position is Earth's negated, one astronomical unit's light
    /// time earlier, on the ecliptic of that earlier time.
    @Test("The Sun's position is Earth's, backdated by the light time of one au")
    func sunPosition() throws {
        let time = Self.time(tt: 9_500.75)
        let earlier = time.adding(days: -1 / Engine.speedOfLightAUPerDay)
        let earth = try Engine.Planet.earth.heliocentricPosition(at: earlier)
        let expected = Engine.Ecliptic(Engine.Vector(x: -earth.x, y: -earth.y, z: -earth.z, time: earlier))
        let sun = try Positions.sunPosition(at: time)
        #expect(sun.longitude == expected.longitude && sun.latitude == expected.latitude)
        #expect(sun.vector.time.tt == time.tt)
    }

    @Test("The heliocentric ecliptic longitude is the heliocentric position's")
    func heliocentricLongitude() throws {
        for tt in Self.grid(count: 20) {
            let time = Self.time(tt: tt)
            for body in Self.bodies(at: tt) where body != .sun {
                let position = try Positions.heliocentricPosition(of: body, at: time)
                #expect(try Positions.eclipticLongitude(of: body, at: time) == Engine.Ecliptic(position).longitude)
            }
        }
        let outside = Self.time(tt: Engine.acceptedTTDays * 2)
        #expect(throws: AstronomyError.invalidBody) { try Positions.eclipticLongitude(of: .sun, at: outside) }
        #expect(throws: AstronomyError.badTime) { try Positions.eclipticLongitude(of: .mars, at: outside) }
        #expect(throws: AstronomyError.invalidBody) { try Positions.eclipticLongitude(of: .io, at: Self.time(tt: 0)) }
    }

    @Test("Bodies the states do not cover throw invalidBody, after the time check")
    func unsupportedBodies() {
        let outside = Self.time(tt: Engine.acceptedTTDays + 1)
        for body: CelestialBody in [.earth, .earthMoonBarycenter, .solarSystemBarycenter, .io, .callisto] {
            for aberration in [Aberration.none, .corrected] {
                #expect(throws: AstronomyError.invalidBody) {
                    try Positions.geocentricEclipticState(of: body, at: Self.time(tt: 0), aberration: aberration)
                }
                #expect(throws: AstronomyError.badTime) {
                    try Positions.geocentricEclipticState(of: body, at: outside, aberration: aberration)
                }
            }
        }
    }

    /// Near the early end of the accepted range the backdated bodies leave
    /// it, and so does the Sun's one-au light time; the Moon is not
    /// backdated.
    @Test("The accepted range bounds the backdated and light-time times")
    func acceptedRange() throws {
        let late = Self.time(tt: Engine.acceptedTTDays)
        let early = Self.time(tt: -Engine.acceptedTTDays)
        _ = try Positions.sunEclipticState(at: late)
        _ = try Positions.sunPosition(at: late)
        #expect(throws: AstronomyError.badTime) { try Positions.sunEclipticState(at: early) }
        #expect(throws: AstronomyError.badTime) { try Positions.sunPosition(at: early) }
        for body in Self.bodies where body != .pluto {
            _ = try Positions.geocentricEclipticState(of: body, at: late, aberration: .corrected)
            if body == .moon {
                _ = try Positions.geocentricEclipticState(of: body, at: early, aberration: .corrected)
            } else {
                #expect(throws: AstronomyError.badTime, "\(body)") {
                    try Positions.geocentricEclipticState(of: body, at: early, aberration: .corrected)
                }
            }
        }
        for time in [Engine.Time.invalid, Self.time(tt: .nan), PlanetTestSupport.time(tt: .infinity)] {
            #expect(throws: AstronomyError.badTime) { try Positions.sunEclipticState(at: time) }
            #expect(throws: AstronomyError.badTime) {
                try Positions.geocentricEclipticState(of: .mars, at: time, aberration: .none)
            }
        }
    }

    // MARK: - Rates

    /// Allowances in degrees, and AU, per day. The position path stops its
    /// light-time iteration at a 1e-9 day residual, so a stencil that
    /// straddles a change in the iteration count sees a step of up to 1e-9
    /// day times the velocity, which the stencil's 8/(12h) = 42.7 per day
    /// amplifies. The Moon's series velocity is a central difference; the
    /// allowances are those `EclipticStateTests` sets for the same quantities.
    static func allowance(_ body: CelestialBody) -> (angle: Double, distance: Double) {
        switch body {
        case .moon: (5e-7, 1e-9)
        case .pluto: (1e-6, 2e-9)
        default: (5e-8, 2e-9)
        }
    }

    /// `state`'s rates against the five-point differences of `position`'s
    /// longitude, latitude and distance at `tt`, each position evaluated
    /// once.
    static func expectRates(
        _ state: Engine.EclipticState, at tt: Double, angle: Double, distance: Double, _ label: String,
        _ position: (Double) throws -> Engine.Ecliptic
    ) throws {
        let h = 1.0 / 64
        let samples = try [tt - 2 * h, tt - h, tt + h, tt + 2 * h].map(position)
        func rate(_ value: (Engine.Ecliptic) -> Double) -> Double {
            let v = samples.map(value)
            return ((v[0] - v[3]) + 8 * (v[2] - v[1])) / (12 * h)
        }
        let longitude = rate { unwrap($0.longitude, near: state.longitude) }
        #expect(abs(longitude - state.longitudeRate) <= angle, "\(label) longitude")
        #expect(abs(rate(\.latitude) - state.latitudeRate) <= angle, "\(label) latitude")
        #expect(abs(rate(\.vector.length) - state.distanceRate) <= distance, "\(label) distance")
    }

    @Test(
        "Rates are the derivatives of the positions on the ecliptic of date", arguments: [Aberration.corrected, .none])
    func rates(aberration: Aberration) throws {
        // The grid, the series beyond the fits, and the 2026 March equinox,
        // where the Sun's longitude wraps through 0.
        for tt in Self.grid(count: 60) + Self.far + [Self.equinox] {
            for body in Self.bodies(at: tt) {
                let state = try Positions.geocentricEclipticState(
                    of: body, at: Self.time(tt: tt), aberration: aberration)
                let (angle, distance) = Self.allowance(body)
                try Self.expectRates(state, at: tt, angle: angle, distance: distance, "\(body) at \(tt)") {
                    try Self.ecliptic(body, tt: $0, aberration)
                }
            }
        }
    }

    /// A stencil center at the 2026 March equinox, TT 9575.116 by the
    /// seasonal roots of `SeasonsTests`, on the 1/64-day grid.
    static let equinox = 9_575.0 + 7.0 / 64

    /// The rate checks above difference longitudes unwrapped near the
    /// state's; at the equinox the stencil's samples lie either side of 0°.
    @Test("The equinox stencil's longitudes straddle the 360° wrap")
    func equinoxWrap() throws {
        let h = 1.0 / 64
        let times = [-2 * h, -h, h, 2 * h].map { Self.equinox + $0 }
        let sun = try times.map { try Positions.sunPosition(at: Self.time(tt: $0)).longitude }
        let geocentric = try times.map { try Self.ecliptic(.sun, tt: $0, .corrected).longitude }
        for longitudes in [sun, geocentric] {
            #expect(longitudes.contains { $0 > 359 } && longitudes.contains { $0 < 1 }, "\(longitudes)")
        }
    }

    @Test("The Sun's rates are the derivatives of its ecliptic position")
    func sunRates() throws {
        for tt in Self.grid(count: 100) + Self.far + [Self.equinox] {
            let state = try Positions.sunEclipticState(at: Self.time(tt: tt))
            try Self.expectRates(state, at: tt, angle: 5e-8, distance: 5e-11, "\(tt)") {
                try Positions.sunPosition(at: Self.time(tt: $0))
            }
        }
    }

    /// The light-time iteration stops when the next backdate moves less than
    /// 1e-9 day, so the number of iterations, and the position's last bits,
    /// change from one instant to the next. The rate comes from the converged
    /// solution, not the iterates, so it stays smooth: adjacent samples 1e-4
    /// day apart differ only by Mercury's acceleration, below 0.2° per day²,
    /// and second differences over 2e-5 day stay below 1e-9° per day.
    @Test("Mercury's rate is smooth across changes in the light-time iteration count")
    func iterationCount() throws {
        let center = 19_590.688_73
        func rate(_ tt: Double) throws -> Double {
            try Positions.geocentricEclipticState(of: .mercury, at: Self.time(tt: tt), aberration: .corrected)
                .longitudeRate
        }
        var counts = Set<Int>()
        var previous: Double?
        for k in -300...300 {
            let tt = center + Double(k) * 1e-4
            let current = try rate(tt)
            if let previous { #expect(abs(current - previous) <= 2e-5, "\(tt)") }
            previous = current
            counts.insert(try Self.iterations(.mercury, tt: tt))
        }
        #expect(counts.count > 1, "the window should see more than one iteration count: \(counts)")
        for k in -30...30 {
            let tt = center + Double(k) * 1e-3
            let d = 2e-5
            let second = try rate(tt - d) - 2 * rate(tt) + rate(tt + d)
            #expect(abs(second) <= 1e-9, "\(tt)")
        }
    }

    /// The number of positions the light-time iteration requests for `body`
    /// seen from Earth with aberration at `tt`.
    static func iterations(_ body: CelestialBody, tt: Double) throws -> Int {
        var count = 0
        _ = try Engine.LightTravel.correct(at: time(tt: tt)) { backdated -> Engine.Vector<Engine.EQJ> in
            count += 1
            let earth = try Positions.heliocentricPosition(of: .earth, at: backdated)
            let target = try Positions.heliocentricPosition(of: body, at: backdated)
            return Engine.Vector(x: target.x - earth.x, y: target.y - earth.y, z: target.z - earth.z, time: backdated)
        }
        return count
    }

    /// The TT at which `body`'s model is evaluated for an observation at
    /// `tt`: the backdated time, or `tt` itself for the Moon, which is not
    /// backdated.
    static func evaluated(_ body: CelestialBody, tt: Double, _ aberration: Aberration) throws -> Double {
        guard body != .moon else { return tt }
        return try Positions.backdatedPosition(of: body, seenFrom: .earth, at: time(tt: tt), aberration: aberration)
            .time.tt
    }

    /// The rates of `body`'s state for observations 1e-10 day either side of
    /// the one whose model is evaluated at `boundary`, within `angle` and
    /// `distance`. Three corrections by the light time find that
    /// observation; the light time changes by about 1e-4 of itself per day,
    /// so each correction shrinks the miss by that factor. The times the
    /// model is evaluated at are checked to straddle `boundary`.
    static func expectContinuous(
        _ body: CelestialBody, across boundary: Double, aberration: Aberration, angle: Double, distance: Double
    ) throws {
        var center = boundary
        for _ in 0..<3 { center += boundary - (try evaluated(body, tt: center, aberration)) }
        let (early, late) = (center - 1e-10, center + 1e-10)
        let (before, after) = (try evaluated(body, tt: early, aberration), try evaluated(body, tt: late, aberration))
        #expect(before < boundary && after > boundary, "\(body) at \(boundary): \(before), \(after)")
        let below = try Positions.geocentricEclipticState(of: body, at: time(tt: early), aberration: aberration)
        let above = try Positions.geocentricEclipticState(of: body, at: time(tt: late), aberration: aberration)
        #expect(abs(below.longitudeRate - above.longitudeRate) <= angle, "\(body) at \(boundary)")
        #expect(abs(below.latitudeRate - above.latitudeRate) <= angle, "\(body) at \(boundary)")
        #expect(abs(below.distanceRate - above.distanceRate) <= distance, "\(body) at \(boundary)")
    }

    /// Earth's and Mercury's polynomial segments are 8 days wide, Venus's
    /// and Mars's 32, and these boundaries are all four's. With aberration
    /// Earth and the target are both evaluated at the backdated time, which
    /// crosses the boundary between the two observations. The fits meet
    /// within 2e-12 AU, and the rates on either side agree as closely.
    @Test("Rates are continuous across polynomial segment boundaries")
    func polynomialSeams() throws {
        for k in [100, 1_000, 4_000, 7_000] {
            let boundary = Engine.PlanetPolynomial.start + Double(k) * 8
            for body: CelestialBody in [.sun, .mercury, .venus, .mars] {
                try Self.expectContinuous(body, across: boundary, aberration: .corrected, angle: 1e-9, distance: 1e-11)
            }
        }
    }

    /// The Moon's DE440 span blends into the lunar series over 32 days at
    /// each end, with a weight whose first two derivatives are continuous.
    @Test("The Moon's rates are continuous through its blends")
    func lunarBlends() throws {
        let ephemeris = Engine.MoonEphemeris.self
        for end in [
            ephemeris.fullWeightStart - ephemeris.blendDays, ephemeris.fullWeightStart, ephemeris.fullWeightEnd,
            ephemeris.fullWeightEnd + ephemeris.blendDays,
        ] {
            try Self.expectContinuous(.moon, across: end, aberration: .none, angle: 5e-7, distance: 1e-9)
        }
    }

    // MARK: - Stations

    /// Bisects `f` for a sign change on [lo, hi] to `tolerance` days.
    static func root(_ f: (Double) throws -> Double, lo: Double, hi: Double, tolerance: Double) throws -> Double? {
        var (lo, hi) = (lo, hi)
        var low = try f(lo)
        guard low * (try f(hi)) <= 0 else { return nil }
        while hi - lo > tolerance {
            let mid = (lo + hi) / 2
            let value = try f(mid)
            if low * value <= 0 {
                hi = mid
            } else {
                (lo, low) = (mid, value)
            }
        }
        return (lo + hi) / 2
    }

    /// Mercury turned retrograde to direct on 2025-08-11. The root of the
    /// analytic longitude rate and the root of the differenced longitude
    /// agree within a second.
    @Test("Mercury's 2025-08-11 station from the rate agrees with the differenced longitude")
    func mercuryStation() throws {
        let center = Engine.Time(
            ut: Engine.Time.days(year: 2_025, month: 8, day: 11, hour: 12, minute: 0, second: 0),
            deltaTModel: .espenakMeeus
        ).tt
        let analytic = try Self.root(
            {
                try Positions.geocentricEclipticState(of: .mercury, at: Self.time(tt: $0), aberration: .corrected)
                    .longitudeRate
            }, lo: center - 1, hi: center + 1, tolerance: 1e-7)
        let differenced = try Self.root(
            { tt in
                try Self.fivePoint(
                    { Self.unwrap(try Self.ecliptic(.mercury, tt: $0, .corrected).longitude, near: 180) }, at: tt,
                    step: 1.0 / 128)
            }, lo: center - 1, hi: center + 1, tolerance: 1e-7)
        let a = try #require(analytic)
        let d = try #require(differenced)
        #expect(abs(a - d) * 86_400 < 1, "\(abs(a - d) * 86_400) s")
    }
}

extension PlutoSegmentSuites {
    /// Pluto's ecliptic state through the DE440 blend at 1900 and in the
    /// integrated model before it, which reads a segment of the model.
    @Suite("Engine Pluto ecliptic states through the blend and the model")
    struct EnginePlutoEclipticStateTests {
        typealias Tests = EngineEclipticStateTests

        @Test("Pluto's rates are the derivatives of its positions in the model and the blend")
        func rates() throws {
            // In the model, mid-blend, and astride the model's 146-day step at
            // TT −36,938, offset by Pluto's light time so the backdated times
            // the stencil evaluates cross it.
            let step = -36_938.0
            let lightTime = step - (try Tests.evaluated(.pluto, tt: step, .corrected))
            let astride = ((step + lightTime) * 1_024).rounded() / 1_024
            let h = 1.0 / 64
            for aberration in [Aberration.corrected, .none] {
                let first = try Tests.evaluated(.pluto, tt: astride - 2 * h, aberration)
                let last = try Tests.evaluated(.pluto, tt: astride + 2 * h, aberration)
                #expect(first < step && last > step, "\(first), \(last)")
            }
            for tt in [-37_000.25, -36_540.5, astride] {
                for aberration in [Aberration.corrected, .none] {
                    let state = try Engine.Positions.geocentricEclipticState(
                        of: .pluto, at: Tests.time(tt: tt), aberration: aberration)
                    let (angle, distance) = Tests.allowance(.pluto)
                    try Tests.expectRates(state, at: tt, angle: angle, distance: distance, "\(tt)") {
                        try Tests.ecliptic(.pluto, tt: $0, aberration)
                    }
                }
            }
        }

        /// The blend's weight has continuous first and second derivatives,
        /// so the rates meet at both ends of the blend.
        @Test("Pluto's rates are continuous at the ends of the 1900 blend")
        func blendEnds() throws {
            let start = Engine.MoonEphemeris.fullWeightStart
            for end in [start - Engine.MoonEphemeris.blendDays, start] {
                try Tests.expectContinuous(.pluto, across: end, aberration: .corrected, angle: 1e-9, distance: 1e-11)
            }
        }
    }
}

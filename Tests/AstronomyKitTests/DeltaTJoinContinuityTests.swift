import Testing

@testable import AstronomyKit

/// Rates and light travel corrections across the points where the default Delta T model's
/// pieces meet with a step. A stencil stepped in UT would see TT jump there, and its rate
/// would be off by the step times the body's speed over the stencil spacing: for the Moon at
/// the 0.088 s Espenak–Meeus step of 1900, up to 7e-5 degrees per day in the rate and 0.2
/// degrees per day squared in a one-minute difference of rates. The stencils step on both
/// clocks instead, so the rates agree with an independent stencil evenly spaced in TT.
@Suite("Delta T join continuity")
struct DeltaTJoinContinuityTests {
    /// The Espenak–Meeus joins inside 1800–2199 where the default model steps: before 1962
    /// it is Espenak–Meeus, and from 1962 the observed table is continuous.
    static let joins: [Double] = [1800, 1860, 1900, 1920, 1941, 1961]

    static let bodies: [CelestialBody] = [.sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn]

    /// The UT of an Espenak–Meeus join: its polynomials take y = 2000 + (ut − 14) / 365.24217.
    static func joinUT(year: Double) -> Double { 14 + (year - 2000) * 365.24217 }

    static func longitude(_ body: CelestialBody, at time: AstroTime) throws -> Double {
        switch body {
        case .sun: try Sun.position(at: time).longitude
        case .moon: try Moon.ecliptic(at: time).longitude
        default: try body.geocentricPosition(at: time).toEcliptic().longitude
        }
    }

    static func state(_ body: CelestialBody, at time: AstroTime) throws -> EclipticState {
        switch body {
        case .sun: try Sun.eclipticState(at: time)
        case .moon: try Moon.eclipticState(at: time)
        default: try body.geocentricEclipticState(at: time)
        }
    }

    /// First and second derivatives of longitude from positions 0.01 TT day apart.
    static func reference(_ body: CelestialBody, at time: AstroTime) throws -> (rate: Double, acceleration: Double) {
        let h = 0.01
        let center = try longitude(body, at: time)
        func offset(_ multiple: Double) throws -> Double {
            (try longitude(body, at: time.addingTerrestrialDays(multiple * h)) - center).remainder(dividingBy: 360)
        }
        let (m2, m1, p1, p2) = (try offset(-2), try offset(-1), try offset(1), try offset(2))
        return ((m2 - 8 * m1 + 8 * p1 - p2) / (12 * h), (16 * (p1 + m1) - p2 - m2) / (12 * h * h))
    }

    @Test("The default model steps at each listed join", arguments: joins)
    func modelStepsAtJoin(year: Double) {
        let ut = Self.joinUT(year: year)
        let before = AstroTime(ut: ut - 1e-6)
        let after = AstroTime(ut: ut + 1e-6)
        let stepSeconds = ((after.terrestrialTime - before.terrestrialTime) - 2e-6) * 86_400
        #expect(abs(stepSeconds) > 0.0005, "the \(Int(year)) join steps by \(stepSeconds) s")
    }

    @Test("A TT offset never steps where addingDays does", arguments: joins)
    func terrestrialOffsetDoesNotStep(year: Double) {
        let start = AstroTime(ut: Self.joinUT(year: year) - 0.01)
        let shifted = start.addingTerrestrialDays(0.02)
        // Within the rounding of a day count near -60,000.
        #expect(abs((shifted.terrestrialTime - start.terrestrialTime) - 0.02) < 1e-10)
        #expect(abs((shifted.universalTime - start.universalTime) - 0.02) < 1e-10)
        let added = start.addingDays(0.02)
        #expect(abs((added.terrestrialTime - start.terrestrialTime) - 0.02) * 86_400 > 0.0005)
    }

    /// Every 20 s for 0.2 day either side of the join, which covers every position of the
    /// ±1/8-day state stencil, its one-minute difference, and the light travel times.
    @Test(
        "Rates and one-minute rate differences agree with a TT stencil across each join",
        arguments: bodies, joins
    )
    func ratesAgreeAcrossJoin(body: CelestialBody, year: Double) throws {
        let join = Self.joinUT(year: year)
        let width = 0.0007
        var largestRateError = 0.0
        var largestAccelerationError = 0.0
        var offset = -0.2
        while offset <= 0.2 {
            let time = AstroTime(ut: join + offset)
            let reference = try Self.reference(body, at: time)
            let rate = try Self.state(body, at: time).longitudeRate
            let before = try Self.state(body, at: time.addingTerrestrialDays(-width / 2)).longitudeRate
            let after = try Self.state(body, at: time.addingTerrestrialDays(width / 2)).longitudeRate
            largestRateError = max(largestRateError, abs(rate - reference.rate))
            largestAccelerationError = max(
                largestAccelerationError,
                abs((after - before) / width - reference.acceleration)
            )
            offset += 20.0 / 86_400
        }
        #expect(largestRateError < 1e-5, "\(body) at \(Int(year)): rate off by \(largestRateError)°/day")
        #expect(
            largestAccelerationError < 0.0005,
            "\(body) at \(Int(year)): acceleration off by \(largestAccelerationError)°/day²"
        )
    }

    /// The Sun's light travel correction backdates its time by about 499 s. Where the
    /// backdated time crosses a join, it must move with TT alone, so the apparent position
    /// stays continuous: a TT step there would move it by the step times the Sun's speed.
    @Test("The Sun's light-time-corrected position is continuous across each join", arguments: joins)
    func sunPositionContinuous(year: Double) throws {
        let lightTime = 499.004_784 / 86_400
        let before = AstroTime(ut: Self.joinUT(year: year) + lightTime - 1e-6)
        let after = before.addingTerrestrialDays(2e-6)
        let change = try Sun.position(at: after).longitude - Sun.position(at: before).longitude
        let expected = try Sun.eclipticState(at: before).longitudeRate * 2e-6
        // A 0.01 s step in TT would move the Sun by about 1.2e-7°.
        #expect(abs(change - expected) < 1e-8, "\(Int(year)): \(change)° against \(expected)°")
    }
}

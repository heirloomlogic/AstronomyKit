import AstronomyKit
import Testing

@Suite("Ecliptic State")
struct EclipticStateTests {
    static let times = [
        AstroTime(year: 1_950, month: 3, day: 1),
        AstroTime(year: 2_026, month: 7, day: 24),
        AstroTime(year: 2_100, month: 12, day: 31, hour: 18),
    ]

    static let planets: [CelestialBody] = [
        .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
    ]

    /// Longitude change from `a` to `b` across the 0/360 seam.
    static func longitudeChange(_ a: Double, _ b: Double) -> Double {
        var change = b - a
        if change > 180 { change -= 360 } else if change < -180 { change += 360 }
        return change
    }

    @Test("Position fields match geocentricPosition().toEcliptic() bit for bit", arguments: times)
    func geocentricPositionMatches(time: AstroTime) throws {
        for body in Self.planets {
            for aberration in [Aberration.corrected, .none] {
                let state = try body.geocentricEclipticState(at: time, aberration: aberration)
                let position = try body.geocentricPosition(at: time, aberration: aberration).toEcliptic()
                #expect(state.ecliptic == position, "\(body) \(aberration)")
                #expect(state.time == time)
            }
        }
    }

    @Test("Sun and Moon position fields match their dedicated functions bit for bit", arguments: times)
    func sunAndMoonMatch(time: AstroTime) throws {
        #expect(try Sun.eclipticState(at: time).ecliptic == Sun.position(at: time))
        #expect(try Moon.eclipticState(at: time).ecliptic == Moon.ecliptic(at: time))
    }

    /// Simpson's rule over a quarter day integrates the rates back to the change
    /// in position. Its own error there is below 1e-8 degrees for the Moon, so the
    /// budgets leave room only for the central difference's truncation and for a
    /// stencil that straddles a change in the light-time iteration count.
    @Test("Rates integrate to the change in position over a quarter day", arguments: times)
    func ratesIntegrateToPosition(time: AstroTime) throws {
        let tt = time.terrestrialTime
        let samples = [tt, tt + 0.125, tt + 0.25].map { AstroTime(tt: $0) }
        for body in Self.planets {
            let states = try samples.map { try body.geocentricEclipticState(at: $0) }
            func simpson(_ rate: (EclipticState) -> Double) -> Double {
                0.25 * (rate(states[0]) + 4 * rate(states[1]) + rate(states[2])) / 6
            }
            let longitude = Self.longitudeChange(states[0].longitude, states[2].longitude)
            #expect(abs(simpson(\.longitudeRate) - longitude) < 1e-6, "\(body) longitude")
            #expect(abs(simpson(\.latitudeRate) - (states[2].latitude - states[0].latitude)) < 1e-6, "\(body) latitude")
            #expect(abs(simpson(\.distanceRate) - (states[2].distance - states[0].distance)) < 1e-8, "\(body) distance")
        }
    }

    @Test("Rates fall in each body's physical range", arguments: times)
    func ratesArePhysical(time: AstroTime) throws {
        let sun = try Sun.eclipticState(at: time)
        #expect((0.95...1.02).contains(sun.longitudeRate))
        let moon = try Moon.eclipticState(at: time)
        #expect((11.7...15.5).contains(moon.longitudeRate))
        #expect(abs(moon.latitudeRate) < 1.5)
        let mercury = try CelestialBody.mercury.geocentricEclipticState(at: time)
        #expect((-1.5...2.3).contains(mercury.longitudeRate))
    }

    /// Before 1962 the default Delta T is Espenak-Meeus, whose polynomials step at
    /// their joins (-0.036 s at 1800-01-15 01:36 UT, +0.050 s at 1860-01-15 14:19,
    /// -0.088 s at 1900-01-15 06:48). Each time here puts a join between the center
    /// sample and the +1/16-day sample, so a stencil offset in UT would carry the step
    /// into the Moon's rate as an error of up to 1e-4 degrees per day.
    @Test(
        "Moon rates match a TT central difference across Delta T joins",
        arguments: [
            AstroTime(year: 1_800, month: 1, day: 15),
            AstroTime(year: 1_860, month: 1, day: 15, hour: 14),
            AstroTime(year: 1_900, month: 1, day: 15, hour: 6),
        ])
    func ratesAcrossDeltaTJoin(time: AstroTime) throws {
        let state = try Moon.eclipticState(at: time)
        let h = 30.0 / 86_400
        let before = try Moon.ecliptic(at: AstroTime(tt: time.terrestrialTime - h))
        let after = try Moon.ecliptic(at: AstroTime(tt: time.terrestrialTime + h))
        let longitudeRate = Self.longitudeChange(before.longitude, after.longitude) / (2 * h)
        #expect(abs(state.longitudeRate - longitudeRate) < 1e-6)
        #expect(abs(state.latitudeRate - (after.latitude - before.latitude) / (2 * h)) < 1e-6)
        #expect(abs(state.distanceRate - (after.distance - before.distance) / (2 * h)) < 1e-10)
    }

    /// Where Delta T steps forward, TT skips the values between the two sides of the
    /// step, so no UT has those TTs and `AstroTime(tt:)` returns one whose TT is off by
    /// up to the step. Each TT here sits in the middle of such a gap (+0.050 s at
    /// 1860-01-15 14:18:31 UT, +0.012 s at 1920-01-16 03:02:00, +0.0009 s at
    /// 1941-01-15 05:05:14), and the state is taken 1/16 day earlier, so its +1/16-day
    /// sample lands in the gap.
    @Test(
        "Moon rates hold when a sample's TT falls in a forward Delta T step",
        arguments: [-51_119.903_712_096, -29_205.373_354_701_32, -21_535.287_743_278_97])
    func ratesAcrossDeltaTGap(gapTT: Double) throws {
        // The condition under test: the sample's TT has no exact UT.
        #expect(AstroTime(tt: gapTT).terrestrialTime != gapTT)
        let time = AstroTime(tt: gapTT - 1.0 / 16)
        let state = try Moon.eclipticState(at: time)
        let h = 30.0 / 86_400
        let before = try Moon.ecliptic(at: AstroTime(tt: time.terrestrialTime - h))
        let after = try Moon.ecliptic(at: AstroTime(tt: time.terrestrialTime + h))
        let longitudeRate = Self.longitudeChange(before.longitude, after.longitude) / (2 * h)
        #expect(abs(state.longitudeRate - longitudeRate) < 1e-6)
        #expect(abs(state.latitudeRate - (after.latitude - before.latitude) / (2 * h)) < 1e-6)
        #expect(abs(state.distanceRate - (after.distance - before.distance) / (2 * h)) < 1e-10)
    }

    /// The Moon crosses 0° longitude about once a month; the rate must stay near
    /// +13°/day there instead of jumping by 360° divided by the stencil.
    @Test("Longitude rate is continuous across the 0/360 seam")
    func rateAcrossSeam() throws {
        let start = AstroTime(year: 2_026, month: 1, day: 1)
        var time = start
        var crossed = false
        var previous = try Moon.ecliptic(at: time).longitude
        while time.terrestrialTime < start.terrestrialTime + 30 {
            time = time.addingHours(1)
            let longitude = try Moon.ecliptic(at: time).longitude
            if longitude < previous {
                crossed = true
                let state = try Moon.eclipticState(at: time.addingHours(-0.5))
                #expect((11.7...15.5).contains(state.longitudeRate))
            }
            previous = longitude
        }
        #expect(crossed)
    }

    @Test("Bodies without a geocentric ecliptic state throw invalidBody")
    func unsupportedBodies() {
        let time = AstroTime(year: 2_026, month: 1, day: 1)
        for body in [CelestialBody.earth, .earthMoonBarycenter, .solarSystemBarycenter, .io] {
            #expect(throws: AstronomyError.invalidBody, "\(body)") {
                _ = try body.geocentricEclipticState(at: time)
            }
        }
    }
}

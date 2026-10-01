import Foundation
import Testing

@testable import AstronomyKit

/// `Sun.altitudeObservation` returns the geometric altitude with the inputs
/// that produced it and the derived terms of the error budget, and refuses the
/// cases the budget excludes. Nothing here changes the process default model.
@Suite("Solar altitude observation")
struct SolarAltitudeObservationTests {
    private static let observer40N = Observer(latitude: 40, longitude: 0)
    private static let j2000UnixOffset = 946_728_000.0

    private static func date(_ iso8601: String) throws -> Date {
        try #require(ISO8601DateFormatter().date(from: iso8601))
    }

    /// The civil `Date` whose day count since J2000 noon is `civilDays`.
    private static func date(civilDays: Double) -> Date {
        Date(timeIntervalSince1970: civilDays * 86_400 + j2000UnixOffset)
    }

    private static func geometricAltitude(_ time: AstroTime) throws -> Double {
        try CelestialBody.sun.horizon(at: time, from: observer40N, refraction: .none).altitude
    }

    @Test("Each entry point evaluates the matching initializer's time")
    func entryPointsMatchHorizon() throws {
        let date = try Self.date("2026-07-24T06:30:00Z")
        let time = AstroTime(date, deltaTModel: .jplHorizons)

        let civil = try Sun.altitudeObservation(at: date, from: Self.observer40N, deltaTModel: .jplHorizons)
        #expect(civil.time.universalTime == time.universalTime)
        #expect(civil.time.terrestrialTime == time.terrestrialTime)
        #expect(civil.time.deltaTModel == .jplHorizons)
        #expect(civil.deltaTModel == .jplHorizons)
        #expect(civil.observer == Self.observer40N)
        #expect(civil.reference == .civilUTC)
        #expect(civil.altitude == (try Self.geometricAltitude(time)))

        let terrestrial = try Sun.altitudeObservation(
            terrestrialTime: time.terrestrialTime, from: Self.observer40N, deltaTModel: .jplHorizons)
        let fromTT = AstroTime(tt: time.terrestrialTime, deltaTModel: .jplHorizons)
        #expect(terrestrial.reference == .terrestrialTime)
        #expect(terrestrial.time.terrestrialTime == time.terrestrialTime)
        #expect(terrestrial.time.universalTime == fromTT.universalTime)
        #expect(terrestrial.altitude == (try Self.geometricAltitude(fromTT)))

        let universal = try Sun.altitudeObservation(
            universalTime: time.universalTime, from: Self.observer40N, deltaTModel: .jplHorizons)
        let fromUT = AstroTime(ut: time.universalTime, deltaTModel: .jplHorizons)
        #expect(universal.reference == .universalTime)
        #expect(universal.time.universalTime == time.universalTime)
        #expect(universal.time.terrestrialTime == fromUT.terrestrialTime)
        #expect(universal.altitude == (try Self.geometricAltitude(fromUT)))

        // The same inputs give the same value and the same bound.
        let again = try Sun.altitudeObservation(at: date, from: Self.observer40N, deltaTModel: .jplHorizons)
        #expect(again == civil)
        #expect(again.hashValue == civil.hashValue)
    }

    @Test("Each construction sums its own terms of the budget")
    func termsFollowTheConstruction() throws {
        let light = SolarAltitudeBounds.lightTimeDegrees
        let era = SolarAltitudeBounds.eraDegrees

        let civil = try Sun.altitudeObservation(
            at: try Self.date("1972-07-01T12:00:00Z"), from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(civil.reference == .civilUTC)
        #expect(civil.errorBound.civilConversion == SolarAltitudeBounds.civilToTTDegrees)
        #expect(civil.errorBound.scaleConversion == SolarAltitudeBounds.ttInverseDegrees)

        let proxy = try Sun.altitudeObservation(
            at: try Self.date("1950-06-01T12:00:00Z"), from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(proxy.reference == .civilUT1)
        #expect(proxy.errorBound.civilConversion == SolarAltitudeBounds.civilToUTDegrees)
        #expect(proxy.errorBound.scaleConversion == SolarAltitudeBounds.forwardTTDegrees)

        let terrestrial = try Sun.altitudeObservation(
            terrestrialTime: 9_000.25, from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(terrestrial.errorBound.civilConversion == 0)
        #expect(terrestrial.errorBound.scaleConversion == SolarAltitudeBounds.ttInverseDegrees)

        let universal = try Sun.altitudeObservation(
            universalTime: 9_000.25, from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(universal.errorBound.civilConversion == 0)
        #expect(universal.errorBound.scaleConversion == SolarAltitudeBounds.forwardTTDegrees)

        for observation in [civil, proxy, terrestrial, universal] {
            let bound = observation.errorBound
            #expect(bound.lightTimeTermination == light)
            #expect(bound.earthRotationAngle == era)
            let plainSum = bound.civilConversion + bound.scaleConversion + light + era
            #expect(bound.total >= plainSum)
            #expect(bound.total <= plainSum.nextUp.nextUp.nextUp)
        }
        // The inverse dominates; the UT-defined constructions are an order smaller.
        #expect(terrestrial.errorBound.total > 8e-9 && terrestrial.errorBound.total < 9e-9)
        #expect(universal.errorBound.total > 1.1e-9 && universal.errorBound.total < 1.2e-9)
    }

    @Test("A rounded sum is moved up to cover the exact sum")
    func addingUp() {
        typealias Bound = SolarAltitudeObservation.ErrorBound
        // 1 + 2^-53 ties to 1; the exact sum is above it.
        #expect(Bound.addingUp(1, Double.ulpOfOne / 2) == 1.0.nextUp)
        // 1 + 0.75 ulp rounds up already; no second step.
        #expect(Bound.addingUp(1, 0.75 * Double.ulpOfOne) == 1.0.nextUp)
        // Exact sums are untouched.
        #expect(Bound.addingUp(0.25, 0.5) == 0.75)
        #expect(Bound.addingUp(1, 0) == 1)
        #expect(Bound.addingUp(1, -Double.ulpOfOne / 2) == 1.0.nextDown)
    }

    @Test("The model is an input, not an error: 2049-12-21T12:00Z under both models")
    func modelIsAnInput() throws {
        let date = try Self.date("2049-12-21T12:00:00Z")
        let em = try Sun.altitudeObservation(at: date, from: Self.observer40N, deltaTModel: .espenakMeeus)
        let jpl = try Sun.altitudeObservation(at: date, from: Self.observer40N, deltaTModel: .jplHorizons)
        #expect(em.time.terrestrialTime == jpl.time.terrestrialTime)
        #expect(abs((jpl.time.universalTime - em.time.universalTime) * 86_400 - 22.950380633) < 1e-6)
        // The two altitudes differ by about 5.2e-4 degrees (DeltaTModelCaptureTests),
        // far above either bound, which describes rounding under one model.
        #expect(abs(em.altitude - jpl.altitude) > 5e-4)
        #expect(em.errorBound.total < 1e-8)
        #expect(jpl.errorBound.total < 1e-8)
    }

    @Test("Times outside the polynomial coverage are refused")
    func coverage() throws {
        let coverage = SolarAltitudeObservation.polynomialCoverage
        #expect(coverage == -36_524.5..<36_889.5)
        typealias Unsupported = SolarAltitudeObservation.Unsupported

        #expect(throws: Unsupported.outsidePolynomialCoverage) {
            try Sun.altitudeObservation(
                at: try Self.date("1899-12-31T12:00:00Z"), from: Self.observer40N, deltaTModel: .espenakMeeus)
        }
        // 2101-01-01T00:00Z civil is 36889.5 days of UTC; TT is 69 s later, past the end.
        #expect(throws: Unsupported.outsidePolynomialCoverage) {
            try Sun.altitudeObservation(
                at: try Self.date("2101-01-01T00:00:00Z"), from: Self.observer40N, deltaTModel: .espenakMeeus)
        }
        _ = try Sun.altitudeObservation(
            at: try Self.date("2100-12-31T23:00:00Z"), from: Self.observer40N, deltaTModel: .espenakMeeus)

        // The light-time loop backdates up to 8.6 minutes; the first minutes of
        // the coverage evaluate the Earth before it.
        let backdate = SolarAltitudeObservation.maximumLightTimeDays
        #expect(backdate > 0.0059 && backdate < 0.006)
        #expect(throws: Unsupported.outsidePolynomialCoverage) {
            try Sun.altitudeObservation(
                terrestrialTime: coverage.lowerBound + backdate / 2, from: Self.observer40N, deltaTModel: .espenakMeeus)
        }
        _ = try Sun.altitudeObservation(
            terrestrialTime: coverage.lowerBound + backdate + 1e-3, from: Self.observer40N, deltaTModel: .espenakMeeus)

        // The last UT whose TT is inside the coverage is accepted; the next one is not.
        let deltaTDays = AstronomyConfig.deltaTEspenakMeeus(universalTime: coverage.upperBound) / 86_400
        _ = try Sun.altitudeObservation(
            universalTime: coverage.upperBound - deltaTDays - 1e-6, from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(throws: Unsupported.outsidePolynomialCoverage) {
            try Sun.altitudeObservation(
                universalTime: coverage.upperBound - deltaTDays + 1e-6, from: Self.observer40N,
                deltaTModel: .espenakMeeus)
        }
    }

    @Test("A TT inside a Delta T gap is refused; a TT with two UTs is accepted")
    func deltaTGaps() throws {
        // The engine's year is 2000 + (ut - 14) / 365.24217; the pieces meet at whole years.
        func boundary(year: Double) -> Double { 14 + (year - 2_000) * 365.24217 }
        func forward(_ ut: Double) -> Double { ut + AstronomyConfig.deltaTEspenakMeeus(universalTime: ut) / 86_400 }

        // 1961: Delta T steps up by 0.0296 s, leaving TT values with no UT.
        let gapBoundary = boundary(year: 1_961)
        let below = forward(gapBoundary - 1e-6)
        let above = forward(gapBoundary + 1e-6)
        #expect(abs((above - below - 2e-6) * 86_400 - 0.0296) < 0.001)
        let inGap = (below + above) / 2
        let clamped = AstroTime(tt: inGap, deltaTModel: .espenakMeeus)
        #expect(clamped.terrestrialTime == inGap)
        let tolerance = max(1e-12, 2 * Double.ulpOfOne * abs(inGap))
        #expect(abs(inGap - forward(clamped.universalTime)) > tolerance)
        #expect(throws: SolarAltitudeObservation.Unsupported.terrestrialTimeInDeltaTGap) {
            try Sun.altitudeObservation(terrestrialTime: inGap, from: Self.observer40N, deltaTModel: .espenakMeeus)
        }
        // Either side of the gap is an ordinary TT.
        for edge in [below - 1e-6, above + 1e-6] {
            _ = try Sun.altitudeObservation(terrestrialTime: edge, from: Self.observer40N, deltaTModel: .espenakMeeus)
        }

        // 2005: Delta T steps down by 0.05 s, so a TT just before the boundary
        // has two UTs; the inverse converges to one and the budget applies.
        let overlapBoundary = boundary(year: 2_005)
        let twoSolutions = forward(overlapBoundary - 1e-7)
        let observation = try Sun.altitudeObservation(
            terrestrialTime: twoSolutions, from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(observation.time.terrestrialTime == twoSolutions)
        #expect(observation.errorBound.scaleConversion == SolarAltitudeBounds.ttInverseDegrees)
    }

    @Test("A civil date at a UTC segment start is refused; a second away is accepted")
    func civilSegmentStarts() throws {
        typealias Unsupported = SolarAltitudeObservation.Unsupported
        // The table's first segment (1961-01-01) and a leap second (1972-07-01).
        for start in [CivilTime.segments[0].start, CivilTime.segments[13].start] {
            #expect(throws: Unsupported.civilDateAtSegmentStart) {
                try Sun.altitudeObservation(
                    at: Self.date(civilDays: start), from: Self.observer40N, deltaTModel: .espenakMeeus)
            }
            #expect(throws: Unsupported.civilDateAtSegmentStart) {
                try Sun.altitudeObservation(
                    at: Self.date(civilDays: start + SolarAltitudeBounds.civilCalendarDays / 2),
                    from: Self.observer40N, deltaTModel: .espenakMeeus)
            }
            let before = try Sun.altitudeObservation(
                at: Self.date(civilDays: start - 1 / 86_400), from: Self.observer40N, deltaTModel: .espenakMeeus)
            let after = try Sun.altitudeObservation(
                at: Self.date(civilDays: start + 1 / 86_400), from: Self.observer40N, deltaTModel: .espenakMeeus)
            #expect(after.time.universalTime > before.time.universalTime)
        }
        // The first segment start separates the UT1 proxy from the table.
        let proxy = try Sun.altitudeObservation(
            at: Self.date(civilDays: CivilTime.segments[0].start - 1 / 86_400),
            from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(proxy.reference == .civilUT1)
        let table = try Sun.altitudeObservation(
            at: Self.date(civilDays: CivilTime.segments[0].start + 1 / 86_400),
            from: Self.observer40N, deltaTModel: .espenakMeeus)
        #expect(table.reference == .civilUTC)
    }

    @Test("Observers outside the budget or the validated range are refused")
    func observers() throws {
        typealias Unsupported = SolarAltitudeObservation.Unsupported
        #expect(SolarAltitudeObservation.maximumObserverHeight == 10_000)
        let tt = 9_000.25
        _ = try Sun.altitudeObservation(
            terrestrialTime: tt, from: Observer(latitude: 40, longitude: 0, height: 10_000), deltaTModel: .espenakMeeus)
        _ = try Sun.altitudeObservation(
            terrestrialTime: tt, from: Observer(latitude: -90, longitude: 180, height: -10_000),
            deltaTModel: .espenakMeeus)
        for height in [Double(10_000).nextUp, Double(-10_000).nextDown, Observer.geocentric.height] {
            #expect(throws: Unsupported.observerHeightOutsideBudget) {
                try Sun.altitudeObservation(
                    terrestrialTime: tt, from: Observer(latitude: 40, longitude: 0, height: height),
                    deltaTModel: .espenakMeeus)
            }
        }
        for observer in [
            Observer(latitude: 91, longitude: 0), Observer(latitude: .nan, longitude: 0),
            Observer(latitude: 0, longitude: .infinity), Observer(latitude: 0, longitude: 0, height: .nan),
        ] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Sun.altitudeObservation(terrestrialTime: tt, from: observer, deltaTModel: .espenakMeeus)
            }
        }
    }

    @Test("Non-finite times throw badTime")
    func nonFiniteTimes() {
        #expect(throws: AstronomyError.badTime) {
            try Sun.altitudeObservation(terrestrialTime: .nan, from: Self.observer40N, deltaTModel: .espenakMeeus)
        }
        #expect(throws: AstronomyError.badTime) {
            try Sun.altitudeObservation(universalTime: .infinity, from: Self.observer40N, deltaTModel: .jplHorizons)
        }
        #expect(throws: AstronomyError.badTime) {
            try Sun.altitudeObservation(
                at: Date(timeIntervalSince1970: .nan), from: Self.observer40N, deltaTModel: .espenakMeeus)
        }
    }

    @Test("Public constants mirror the generated bounds")
    func constants() {
        #expect(SolarAltitudeObservation.polynomialSegmentDays == 8)
        #expect(SolarAltitudeObservation.joinDiscontinuityDegrees == SolarAltitudeBounds.joinDegrees)
        #expect(SolarAltitudeObservation.maximumLightTimeDays == SolarAltitudeBounds.backdateMaxDays)
        // Nine thousand one hundred seventy-seven eight-day segments span the coverage.
        let coverage = SolarAltitudeObservation.polynomialCoverage
        let segments = (coverage.upperBound - coverage.lowerBound) / SolarAltitudeObservation.polynomialSegmentDays
        #expect(segments.rounded(.up) == 9_177)
        // Every bound is a small positive angle; the inverse is the largest.
        let bounds = [
            SolarAltitudeBounds.civilToTTDegrees, SolarAltitudeBounds.civilToUTDegrees,
            SolarAltitudeBounds.forwardTTDegrees, SolarAltitudeBounds.lightTimeDegrees,
            SolarAltitudeBounds.eraDegrees, SolarAltitudeBounds.joinDegrees,
        ]
        for bound in bounds {
            #expect(bound > 0 && bound < SolarAltitudeBounds.ttInverseDegrees)
        }
    }
}

//
//  PlutoRangeTests.swift
//  AstronomyKit
//
//  Tests for the Pluto compute denial-of-service guard.
//

import Testing

@testable import AstronomyKit

/// Public Pluto queries accept the engine range and reject invalid observations.
@Suite("Pluto Range")
struct PlutoRangeTests {
    @Test(
        "Every public Pluto position and state path accepts the engine endpoints",
        arguments: [-1_461_000.0, 1_461_000.0, -800_000.0, 800_000.0])
    func engineRangeSucceeds(tt: Double) throws {
        let time = AstroTime(tt: tt)
        _ = try CelestialBody.pluto.heliocentricPosition(at: time)
        _ = try CelestialBody.pluto.heliocentricState(at: time)
        _ = try CelestialBody.pluto.barycentricState(at: time)
        for aberration in [Aberration.none, .corrected] {
            _ = try CelestialBody.pluto.geocentricPosition(at: time, aberration: aberration)
            _ = try CelestialBody.pluto.geocentricEclipticState(at: time, aberration: aberration)
        }
    }

    @Test(
        "Public Pluto rejects times outside the engine range", arguments: [(-1_461_000.0).nextDown, 1_461_000.0.nextUp])
    func outsideRangeThrows(tt: Double) {
        let time = AstroTime(tt: tt)
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.heliocentricPosition(at: time)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.geocentricPosition(at: time)
        }
    }

    /// A NaN TT passes both table-range comparisons and reaches a NaN to
    /// `int` conversion without the guard (#58). `AstroTime(ut: -.infinity)` also has a NaN TT,
    /// because Delta T turns an infinite UT into NaN.
    @Test(
        "Every Pluto position path throws badTime for a non-finite TT",
        arguments: [AstroTime(ut: .nan), AstroTime(tt: .nan), AstroTime(ut: -.infinity), AstroTime(ut: .infinity)]
    )
    func nonFiniteTimeThrows(time: AstroTime) {
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.heliocentricPosition(at: time)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.geocentricPosition(at: time)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.heliocentricState(at: time)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.barycentricState(at: time)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.geocentricEclipticState(at: time)
        }
    }
}

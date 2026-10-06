//
//  PlutoRangeTests.swift
//  AstronomyKit
//
//  Tests for the Pluto compute denial-of-service guard.
//

import Testing

@testable import AstronomyKit

/// Verifies that Pluto queries just beyond the tabulated range still compute,
/// while queries far outside it are rejected quickly instead of triggering an
/// unbounded step-integration.
@Suite("Pluto Range")
struct PlutoRangeTests {
    @Test("Position just beyond the table (year 4090) succeeds")
    func nearRangeSucceeds() throws {
        let time = AstroTime(year: 4_090, month: 1, day: 1)
        _ = try CelestialBody.pluto.heliocentricPosition(at: time)
    }

    @Test("Position far outside the table throws badTime", arguments: [4_200, -200])
    func farOutsideRangeThrows(year: Int) {
        let time = AstroTime(year: year, month: 1, day: 1)
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.pluto.heliocentricPosition(at: time)
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

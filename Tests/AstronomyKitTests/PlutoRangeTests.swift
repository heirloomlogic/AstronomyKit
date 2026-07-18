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
}

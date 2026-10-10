//
//  NativeCutoverTests.swift
//  AstronomyKit
//
//  Public regressions for the defects the C engine had on these paths. Each
//  case keeps the inputs its issue comment recorded.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native cutover regressions")
struct NativeCutoverTests {
    private static let second = 1 / 86_400.0

    /// #92: the C ascent pruning used a quarter-span slope bound and discarded
    /// the Sun's 60° crossing in this 0.42-day window; the public search now
    /// finds it.
    @Test("An altitude crossing inside a scan step with equal-sign endpoints is found")
    func altitudePruning() throws {
        let site = Observer(latitude: 0, longitude: 0)
        let start = AstroTime(ut: 8_000, deltaTModel: .espenakMeeus)
        let culmination = try CelestialBody.sun.culmination(after: start, from: site)
        let lower = culmination.time.addingDays(-0.21)
        let crossing = try #require(
            try CelestialBody.sun.searchAltitude(60, direction: .rise, after: lower, from: site, limitDays: 0.42))
        #expect(crossing > lower)
        #expect(crossing < culmination.time)
    }

    /// #92: a valid short window at the end of the accepted range used to be
    /// evaluated a full 0.42-day step past its end and throw `badTime`.
    @Test("A short window at the accepted boundary returns no event instead of throwing")
    func boundedWindow() throws {
        let start = AstroTime(tt: 1_461_000 - 0.001, deltaTModel: .espenakMeeus)
        let result = try CelestialBody.sun.searchAltitude(
            90, direction: .rise, after: start, from: Observer(latitude: 90, longitude: 0), limitDays: 0.0005)
        #expect(result == nil)
    }

    /// #93: a search that began after the full Moon but before the eclipse
    /// peak used to skip the still-upcoming eclipse.
    @Test("A lunar eclipse search started between the full Moon and the peak finds that eclipse")
    func lunarEclipseStartBoundary() throws {
        let nearJanuaryPeak = IndependentReferenceDate.universal("2000-01-21T04:42:00Z", deltaTModel: .espenakMeeus)
        let fullMoon = try #require(
            try Moon.searchPhase(.full, after: nearJanuaryPeak.addingDays(-1), limitDays: 2))
        let january = try Eclipse.searchLunar(after: fullMoon.addingDays(-Self.second))
        #expect(fullMoon.terrestrialTime < january.peak.terrestrialTime)

        for start in [
            fullMoon,
            fullMoon.addingDays(Self.second),
            january.peak.addingDays(-Self.second),
            january.peak,
            AstroTime(tt: january.peak.terrestrialTime.nextUp, deltaTModel: .espenakMeeus),
        ] {
            let result = try Eclipse.searchLunar(after: start)
            #expect(
                abs(result.peak.terrestrialTime - january.peak.terrestrialTime) * 86_400 <= 1,
                "search start TT \(start.terrestrialTime)")
            #expect(result.peak.terrestrialTime >= start.terrestrialTime)
            #expect(result.kind == january.kind)
        }

        let later = try Eclipse.searchLunar(after: january.peak.addingDays(2 * Self.second))
        #expect(later.peak.terrestrialTime > january.peak.terrestrialTime)
    }

    /// #93: NASA lists 2014-04-29 as a non-central annular and 2043-04-09 as
    /// a non-central total eclipse; the C classification reported both as
    /// partial with no central location.
    @Test(
        "Non-central annular and total eclipses keep their published kind",
        arguments: [(5_231.753159722222, EclipseKind.annular), (15_804.290150462963, .total)])
    func noncentralSolarEclipse(tt: Double, kind: EclipseKind) throws {
        let eclipse = try Eclipse.searchGlobalSolar(after: AstroTime(tt: tt - 10, deltaTModel: .espenakMeeus))
        #expect(eclipse.kind == kind)
        #expect(abs(eclipse.peak.terrestrialTime - tt) * 86_400 < 453.6)
        #expect(eclipse.latitude != nil)
        #expect(eclipse.longitude != nil)
        #expect(eclipse.obscuration > 0 && eclipse.obscuration <= 1)
    }

    /// #92: the sampled apsis refinement returned a point near the left edge
    /// of its last interval, 194 s early against the Horizons bracket.
    @Test("Pluto's 2025 apocenter lands inside sixty seconds of the Horizons bracket")
    func plutoApsis() throws {
        struct Root: Decodable {
            let kind: String
            let lowerJDTT: Double
            let upperJDTT: Double
        }
        struct Case: Decodable {
            let body: String
            let roots: [Root]
        }
        struct Archive: Decodable { let cases: [Case] }
        let root = (0..<3).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let archive = try JSONDecoder().decode(
            Archive.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/reference-data/planetary-apsis-evidence.json")))
        let pluto = try #require(archive.cases.first { $0.body == "pluto" })
        let apocenter = try #require(pluto.roots.first { $0.kind == "apocenter" })
        #expect((apocenter.upperJDTT - apocenter.lowerJDTT) * 86_400 <= 1)

        let start = IndependentReferenceDate.universal("2025-01-01T00:00:00Z", deltaTModel: .espenakMeeus)
        let apsis = try CelestialBody.pluto.searchApsis(after: start)
        #expect(apsis.kind == .apocenter)
        let jd = apsis.time.terrestrialTime + 2_451_545
        #expect(abs(jd - (apocenter.lowerJDTT + apocenter.upperJDTT) / 2) * 86_400 < 60)
    }

    /// #164: months past 14 used to land one or two days late.
    @Test(
        "Calendar components normalize any month",
        arguments: [15, 25, 26, 27, 37, 38, 39, 0, -1, -11, -12, -13, 13, 14])
    func monthNormalization(month: Int) {
        let index = month - 1
        let normalizedMonth = ((index % 12) + 12) % 12 + 1
        let yearCarry = (index - normalizedMonth + 1) / 12
        let normalized = AstroTime(year: 2_001 + yearCarry, month: normalizedMonth, day: 1)
        let given = AstroTime(year: 2_001, month: month, day: 1)
        #expect(given.universalTime == normalized.universalTime, "month \(month)")
        #expect(given.terrestrialTime == normalized.terrestrialTime, "month \(month)")
    }

    /// Owner decision on #168: a time derived from an invalid time stays
    /// invalid. The C engine's `Astronomy_AddDays` derived it with the process
    /// default model instead.
    @Test("A time derived from an invalid time is invalid")
    func derivedInvalidTime() {
        let huge = AstroTime(ut: 1e160, deltaTModel: .espenakMeeus)
        #expect(huge.universalTime == 1e160)
        #expect(!huge.terrestrialTime.isFinite)
        #expect(huge.deltaTModel == nil)

        let derived = huge.addingDays(-1e160)
        #expect(derived.universalTime == 0)
        #expect(derived.terrestrialTime.isNaN)
        #expect(derived.deltaTModel == nil)
        #expect(throws: AstronomyError.badTime) { try Sun.position(at: derived) }
    }
}

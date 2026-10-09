//
//  EngineAngularEventTests.swift
//  AstronomyKit
//
//  Native solar-longitude, season, and relative-longitude searches.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Events angular searches")
struct EngineAngularEventTests {
    static let j2000 = 2_451_545.0
    static let planets: [CelestialBody] = [
        .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
    ]

    static func time(year: Int, month: Int, day: Int, model: DeltaTModel) -> Engine.Time {
        Engine.Time(
            ut: Engine.Time.days(year: year, month: month, day: day, hour: 0, minute: 0, second: 0),
            deltaTModel: model)
    }

    static func write(_ value: Any, environment: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environment] else { return }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    @Test("Seasons use the requested model and remain ordered", arguments: DeltaTModel.allCases)
    func seasonOrdering(model: DeltaTModel) throws {
        let seasons = try Engine.Events.seasons(year: 2025, deltaTModel: model)
        let events = seasons.all
        #expect(events.count == 4)
        #expect(events.map(\.ut) == events.map(\.ut).sorted())
        #expect(events.allSatisfy { $0.deltaTModel == model })
    }

    @Test("All 924 seasons match the independent Horizons and ERFA roots under both models")
    func seasonalReference() throws {
        let expected = try SeasonalEpochTests.loadEvents()
        var failures: [String] = []
        var measurements: [[String: Any]] = []
        for model in DeltaTModel.allCases {
            var worst = (error: 0.0, year: 0, kind: "")
            for year in SeasonalEpochTests.years {
                let offset = (year - SeasonalEpochTests.years.lowerBound) * 4
                let events = try Engine.Events.seasons(year: year, deltaTModel: model).all
                for (actual, reference) in zip(events, expected[offset..<(offset + 4)]) {
                    let error = abs(actual.tt - (reference.referenceJulianDateTT - Self.j2000)) * Engine.secondsPerDay
                    if error > worst.error {
                        worst = (error, year, reference.kind)
                    }
                    if !(error < 60) {
                        failures.append("\(model) \(year) \(reference.kind): \(error) s")
                    }
                }
            }
            measurements.append([
                "model": model == .espenakMeeus ? "espenakMeeus" : "jplHorizons",
                "eventCount": expected.count,
                "worstErrorSeconds": worst.error,
                "worstEvent": "\(worst.year) \(worst.kind)",
                "toleranceSeconds": 60,
            ])
        }
        try Self.write(measurements, environment: "ANGULAR_SEASON_EVIDENCE_OUTPUT")
        #expect(failures.isEmpty, "\(failures.count) events, first \(failures.prefix(3)); \(measurements)")
    }

    @Test("Solar-longitude search preserves inclusive window direction and missing-event nil")
    func solarLongitudeWindow() throws {
        let start = Self.time(year: 2025, month: 3, day: 10, model: .espenakMeeus)
        let forward = try #require(try Engine.Events.searchSunLongitude(0, after: start, limitDays: 20))
        let later = start.adding(days: 20)
        let reversed = try #require(try Engine.Events.searchSunLongitude(0, after: later, limitDays: -20))
        #expect(abs(forward.tt - reversed.tt) * Engine.secondsPerDay < 0.01)
        let january = Self.time(year: 2025, month: 1, day: 1, model: .espenakMeeus)
        #expect(try Engine.Events.searchSunLongitude(0, after: january, limitDays: 1) == nil)
    }

    @Test("A relative-longitude search returns a forward event with its input model", arguments: DeltaTModel.allCases)
    func relativeLongitudeDirection(model: DeltaTModel) throws {
        let start = Self.time(year: 2025, month: 1, day: 1, model: model)
        let event = try Engine.Events.searchRelativeLongitude(of: .mars, targetDegrees: 0, after: start)
        #expect(event.ut >= start.ut)
        #expect(event.deltaTModel == model)
    }

    @Test("Published conjunction and opposition intervals")
    func publishedRelativeLongitude() throws {
        var failures: [String] = []
        var measurements: [[String: Any]] = []
        for reference in IndependentReferenceArchive.shared.relativeLongitudeEvents {
            let body = try #require(["mars": CelestialBody.mars, "venus": .venus][reference.body])
            let sourceStart = IndependentReferenceDate.engine(reference.startUTC)
            let actual = try Engine.Events.searchRelativeLongitude(
                of: body,
                targetDegrees: reference.targetRelativeLongitudeDegrees,
                after: sourceStart)
            let actualJulianDateTT = Self.j2000 + actual.tt
            let scaleDays = reference.timeScaleAllowanceSeconds / Engine.secondsPerDay
            let estimateError = abs(actualJulianDateTT - reference.estimatedJulianDateTDB) * Engine.secondsPerDay
            if actualJulianDateTT < reference.lowerJulianDateTDB - scaleDays
                || actualJulianDateTT > reference.upperJulianDateTDB + scaleDays
                || estimateError > reference.timeToleranceSeconds
                || !(reference.lowerOffsetDegrees < 0 && reference.upperOffsetDegrees > 0)
            {
                failures.append("\(reference.body) \(reference.targetRelativeLongitudeDegrees): \(estimateError) s")
            }
            measurements.append([
                "body": reference.body,
                "targetDegrees": reference.targetRelativeLongitudeDegrees,
                "actualJulianDateTT": actualJulianDateTT,
                "estimateErrorSeconds": estimateError,
                "toleranceSeconds": reference.timeToleranceSeconds,
            ])
        }
        try Self.write(measurements, environment: "ANGULAR_RELATIVE_LONGITUDE_EVIDENCE_OUTPUT")
        #expect(failures.isEmpty, "\(failures.count) events, first \(failures.prefix(3))")
    }

    @Test("Every supported planet reaches a finite forward event with a small angular residual", arguments: planets)
    func supportedPlanet(body: CelestialBody) throws {
        let start = Self.time(year: 2025, month: 1, day: 1, model: .jplHorizons)
        let target = 73.125
        let event = try Engine.Events.searchRelativeLongitude(of: body, targetDegrees: target, after: start)
        let direction = body == .mercury || body == .venus ? -1.0 : 1.0
        let earth = try Engine.Positions.eclipticLongitude(of: .earth, at: event)
        let planet = try Engine.Positions.eclipticLongitude(of: body, at: event)
        let residual = Engine.longitudeOffset(direction * (earth - planet) - target)
        #expect(event.ut >= start.ut)
        #expect(event.deltaTModel == .jplHorizons)
        #expect(abs(residual) < 0.001)
    }

    @Test("Relative-longitude targets wrap by whole turns")
    func wrappedTarget() throws {
        let start = Self.time(year: 2025, month: 1, day: 1, model: .espenakMeeus)
        let direct = try Engine.Events.searchRelativeLongitude(of: .mars, targetDegrees: 90, after: start)
        let wrapped = try Engine.Events.searchRelativeLongitude(
            of: .mars,
            targetDegrees: 90 + 360 * 1_000_000,
            after: start)
        #expect(abs(direct.tt - wrapped.tt) * Engine.secondsPerDay < 1)
    }

    @Test("Unsupported bodies retain their distinct failures")
    func unsupportedBodies() {
        let start = Self.time(year: 2025, month: 1, day: 1, model: .espenakMeeus)
        #expect(throws: AstronomyError.earthNotAllowed) {
            _ = try Engine.Events.searchRelativeLongitude(of: .earth, targetDegrees: 0, after: start)
        }
        for body in CelestialBody.allCases where !Self.planets.contains(body) && body != .earth {
            #expect(throws: AstronomyError.invalidBody, "\(body)") {
                _ = try Engine.Events.searchRelativeLongitude(of: body, targetDegrees: 0, after: start)
            }
        }
    }

    @Test("Nonfinite parameters and times are rejected")
    func invalidInputs() {
        let start = Self.time(year: 2025, month: 1, day: 1, model: .espenakMeeus)
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Engine.Events.searchSunLongitude(value, after: start, limitDays: 20)
            }
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Engine.Events.searchSunLongitude(0, after: start, limitDays: value)
            }
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Engine.Events.searchRelativeLongitude(of: .mars, targetDegrees: value, after: start)
            }
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try Engine.Events.searchSunLongitude(0, after: .invalid, limitDays: 20)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try Engine.Events.searchRelativeLongitude(of: .mars, targetDegrees: 0, after: .invalid)
        }
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try Engine.Events.seasons(year: .max, deltaTModel: .espenakMeeus)
        }
    }

    @Test("Searches do not evaluate beyond the native ephemeris range")
    func sourceRange() {
        let start = Engine.Time(tt: Engine.acceptedTTDays - 1, deltaTModel: .espenakMeeus)
        #expect(throws: AstronomyError.badTime) {
            _ = try Engine.Events.searchSunLongitude(0, after: start, limitDays: 20)
        }
        #expect(throws: AstronomyError.badTime) {
            _ = try Engine.Events.searchRelativeLongitude(of: .mars, targetDegrees: 0, after: start)
        }
    }
}

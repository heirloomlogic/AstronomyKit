//
//  PolarSunriseReconciliationTests.swift
//  AstronomyKitTests
//
//  Retained diagnostics for issue #124's South Pole USNO row.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("South Pole sunrise reconciliation")
struct PolarSunriseReconciliationTests {
    private static let observer = Observer(latitude: -90, longitude: 0, height: 0)
    private static let start = Engine.Time(
        ut: IndependentReferenceDate.universal("2022-01-01T00:00Z", deltaTModel: .espenakMeeus)
            .universalTime,
        deltaTModel: .espenakMeeus)
    private static let reference = Engine.Time(
        ut: IndependentReferenceDate.universal("2022-09-20T21:52Z", deltaTModel: .espenakMeeus)
            .universalTime,
        deltaTModel: .espenakMeeus)
    private static let searchStepDays = 0.42
    private static let searchLimitDays = 366.0
    private static let solarRadiusKilometers = 695_700.0
    private static let averageRefractionDegrees = 34.0 / 60
    private static let usnoFixedCenterDepressionDegrees = 50.0 / 60

    private enum DiagnosticError: Error {
        case rootNotFound
    }

    private struct Bracket {
        let lower: Engine.Time
        let upper: Engine.Time
    }

    @Test("Archived row 2,923 keeps its Universal Time coordinate and allowance")
    func sourceBinding() throws {
        let row = try #require(
            IndependentReferenceArchive.shared.riseSetStreams
                .flatMap(\.events)
                .first { $0.sourceLine == 2_923 })
        #expect(row.body == "sun")
        #expect(row.longitudeDegrees == 0)
        #expect(row.latitudeDegrees == -90)
        #expect(row.utc == "2022-09-20T21:52Z")
        #expect(row.direction == "rise")
        #expect(row.timeToleranceSeconds == 70.8)

        let source = try String(
            contentsOf: Self.repositoryRoot.appendingPathComponent(
                "Scripts/reference-data/sources/riseset.txt"), encoding: .utf8)
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines[2_922] == "Sun     0 -90 2022-09-20T21:52Z r")
    }

    @Test("Public and native apparent-horizon controls reproduce the unresolved residual")
    func residuals() throws {
        let expected = IndependentReferenceDate.universal(
            "2022-09-20T21:52Z", deltaTModel: .espenakMeeus)
        let publicCandidate = try CelestialBody.sun.searchRiseSet(
            direction: .rise,
            after: IndependentReferenceDate.universal(
                "2022-01-01T00:00Z", deltaTModel: .espenakMeeus),
            from: Self.observer,
            limitDays: Self.searchLimitDays)
        let publicRoot = try #require(publicCandidate)
        let publicResidual =
            (publicRoot.terrestrialTime - expected.terrestrialTime) * Engine.secondsPerDay

        let existingRoots = try [10.0, 0.1, 0.01, 0.001].map {
            try Self.root(toleranceSeconds: $0, observable: Self.existingUpperLimb)
        }
        let nativeResidual = Self.signedTTResidual(existingRoots[3])
        let fixedCenter = try Self.root(
            toleranceSeconds: 0.001, observable: Self.topocentricFixedCenter)
        let fixedCenterResidual = Self.signedTTResidual(fixedCenter)
        let geocentric = try Self.root(toleranceSeconds: 0.001, observable: Self.geocentricFixedCenter)
        let geocentricResidual = Self.signedTTResidual(geocentric)
        let bisection = try Self.bisection(observable: Self.existingUpperLimb)

        print(
            "polar-sunrise residuals: public=\(publicResidual), native=\(nativeResidual), "
                + "fixed-center=\(fixedCenterResidual), geocentric=\(geocentricResidual), "
                + "tolerances=\(existingRoots.map(Self.signedTTResidual)), "
                + "bisection=\(Self.signedTTResidual(bisection))")

        // The public search runs on the C engine's IAU 2000B nutation and the
        // native controls on IAU 2006/2000A, which moved them 0.011 s earlier
        // and leaves the native upper-limb control 0.035 s before the public one.
        #expect(abs(publicResidual - 75.985_957_542) < 0.001)
        #expect(abs(nativeResidual - 75.950_547_197) < 0.001)
        #expect(abs(fixedCenterResidual - -220.648_209_279) < 0.001)
        #expect(abs(geocentricResidual - -759.652_990_219) < 0.001)
        #expect(abs(nativeResidual) > 70.8)
        #expect(abs(fixedCenterResidual) > 70.8)
        #expect(abs(geocentricResidual) > 70.8)
        #expect(
            existingRoots.map(Self.signedTTResidual).max()!
                - existingRoots.map(Self.signedTTResidual).min()! < 0.003)
        #expect(abs(Self.signedTTResidual(bisection) - nativeResidual) < 0.001)
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func existingUpperLimb(_ time: Engine.Time) throws -> Double {
        let coordinates = try Engine.Positions.equatorial(
            of: .sun, at: time, from: observer, equatorDate: .ofDate, aberration: .corrected)
        let horizontal = Engine.Horizontal(
            time: time, observer: observer, rightAscension: coordinates.rightAscension,
            declination: coordinates.declination, refraction: .none)
        let angularRadius =
            asin(solarRadiusKilometers / Engine.kilometersPerAU / coordinates.distance)
            * Engine.degreesPerRadian
        return horizontal.altitude + angularRadius + averageRefractionDegrees
    }

    private static func topocentricFixedCenter(_ time: Engine.Time) throws -> Double {
        let horizontal = try Engine.Positions.horizontal(
            of: .sun, at: time, from: observer, refraction: .none)
        return horizontal.altitude + usnoFixedCenterDepressionDegrees
    }

    private static func geocentricFixedCenter(_ time: Engine.Time) throws -> Double {
        let coordinates = try Engine.Positions.equatorial(
            of: .sun, at: time, from: .geocentric, equatorDate: .ofDate, aberration: .corrected)
        let horizontal = Engine.Horizontal(
            time: time, observer: observer, rightAscension: coordinates.rightAscension,
            declination: coordinates.declination, refraction: .none)
        return horizontal.altitude + usnoFixedCenterDepressionDegrees
    }

    private static func bracket(
        observable: (Engine.Time) throws -> Double
    ) throws -> Bracket {
        let end = start.adding(days: searchLimitDays)
        var lower = start
        var lowerValue = try observable(lower)
        while lower.ut < end.ut {
            let upper = lower.adding(days: min(searchStepDays, end.ut - lower.ut))
            let upperValue = try observable(upper)
            if lowerValue <= 0, upperValue >= 0, lowerValue < 0 || upperValue > 0 {
                return Bracket(lower: lower, upper: upper)
            }
            lower = upper
            lowerValue = upperValue
        }
        throw DiagnosticError.rootNotFound
    }

    private static func root(
        toleranceSeconds: Double,
        observable: (Engine.Time) throws -> Double
    ) throws -> Engine.Time {
        let window = try bracket(observable: observable)
        let candidate = try Engine.Search.ascendingRoot(
            from: window.lower, to: window.upper,
            toleranceSeconds: toleranceSeconds, observable)
        return try #require(candidate)
    }

    private static func bisection(
        observable: (Engine.Time) throws -> Double
    ) throws -> Engine.Time {
        let window = try bracket(observable: observable)
        var lower = window.lower
        var upper = window.upper
        for _ in 0..<40 {
            let middle = lower.derived(ut: lower.ut + (upper.ut - lower.ut) / 2)
            if try observable(middle) < 0 {
                lower = middle
            } else {
                upper = middle
            }
        }
        return lower.derived(ut: lower.ut + (upper.ut - lower.ut) / 2)
    }

    private static func signedTTResidual(_ time: Engine.Time) -> Double {
        (time.tt - reference.tt) * Engine.secondsPerDay
    }
}

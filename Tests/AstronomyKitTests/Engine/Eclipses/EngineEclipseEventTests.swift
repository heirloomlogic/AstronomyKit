import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Engine.Events eclipse searches")
struct EngineEclipseEventTests {
    typealias Events = Engine.Events

    static func write(_ value: Any, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["ECLIPSE_EVENT_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
            to: url.appendingPathComponent(name + ".json"))
    }

    @Test("Shadow-disc overlap preserves exact and partial geometries")
    func shadowDiscOverlap() {
        #expect(Engine.Shadows.obscuration(firstRadius: 1, secondRadius: 1, separation: 2) == 0)
        #expect(Engine.Shadows.obscuration(firstRadius: 1, secondRadius: 2, separation: 0) == 1)
        #expect(Engine.Shadows.obscuration(firstRadius: 2, secondRadius: 1, separation: 0) == 0.25)
        let oneRadiusSeparation = Engine.Shadows.obscuration(firstRadius: 1, secondRadius: 1, separation: 1)
        #expect(abs(oneRadiusSeparation - 0.3910022189557706) < 1.0e-15)

        let nearExternal = Engine.Shadows.obscuration(
            firstRadius: 1_737.4, secondRadius: 4_669.7, separation: (1_737.4 + 4_669.7).nextDown)
        let roundedNegative = Engine.Shadows.obscuration(
            firstRadius: 1_737.4, secondRadius: 4_600, separation: (1_737.4 + 4_600).nextDown)
        #expect(0...2.0e-16 ~= nearExternal)
        #expect(0...2.0e-16 ~= roundedNegative)

        let innerTangent = Engine.Shadows.obscuration(firstRadius: 2, secondRadius: 1, separation: 1)
        let nearInner = Engine.Shadows.obscuration(firstRadius: 2, secondRadius: 1, separation: 1.nextUp)
        let nearConcentric = Engine.Shadows.obscuration(
            firstRadius: 1, secondRadius: 1, separation: Double.leastNonzeroMagnitude)
        let hugeScale = Double.greatestFiniteMagnitude / 4
        let hugeEqualRadii = Engine.Shadows.obscuration(
            firstRadius: hugeScale, secondRadius: hugeScale, separation: hugeScale)
        #expect(innerTangent == 0.25)
        #expect(0...0.25 ~= nearInner)
        #expect(0...1 ~= nearConcentric)
        #expect(abs(hugeEqualRadii - oneRadiusSeparation) < 1.0e-15)
    }

    @Test("Lunar shadow boundaries use strict contact geometry")
    func lunarShadowBoundaries() {
        let moon = 1.0
        let umbra = 2.0
        let penumbra = 4.0
        #expect(
            Events.lunarEclipseKind(
                axisDistanceKilometers: 5, umbraRadiusKilometers: umbra, penumbraRadiusKilometers: penumbra,
                moonRadiusKilometers: moon) == nil)
        #expect(
            Events.lunarEclipseKind(
                axisDistanceKilometers: 5.nextDown, umbraRadiusKilometers: umbra, penumbraRadiusKilometers: penumbra,
                moonRadiusKilometers: moon) == .penumbral)
        #expect(
            Events.lunarEclipseKind(
                axisDistanceKilometers: 3, umbraRadiusKilometers: umbra, penumbraRadiusKilometers: penumbra,
                moonRadiusKilometers: moon) == .penumbral)
        #expect(
            Events.lunarEclipseKind(
                axisDistanceKilometers: 3.nextDown, umbraRadiusKilometers: umbra, penumbraRadiusKilometers: penumbra,
                moonRadiusKilometers: moon) == .partial)
        #expect(
            Events.lunarEclipseKind(
                axisDistanceKilometers: 1, umbraRadiusKilometers: umbra, penumbraRadiusKilometers: penumbra,
                moonRadiusKilometers: moon) == .partial)
        #expect(
            Events.lunarEclipseKind(
                axisDistanceKilometers: 0.999_999, umbraRadiusKilometers: umbra, penumbraRadiusKilometers: penumbra,
                moonRadiusKilometers: moon) == .total)
    }

    @Test("NASA lunar eclipses retain type, peak, and phase durations")
    func publishedLunarEclipses() throws {
        var measurements: [[String: Any]] = []
        for reference in IndependentReferenceArchive.shared.lunarEclipses {
            let expected = IndependentReferenceDate.engine(reference.universalTime)
            let actual = try Events.searchLunarEclipse(after: expected.adding(days: -10))
            let peakResidual = abs(actual.peak.tt - expected.tt) * Engine.secondsPerDay
            #expect(actual.kind.rawValue == reference.kind)
            #expect(peakResidual <= reference.toleranceSeconds)
            if let expectedDuration = reference.penumbralSemiDurationMinutes {
                #expect(abs(actual.penumbralDurationMinutes - expectedDuration) <= reference.durationToleranceMinutes)
            }
            #expect(
                abs(actual.partialDurationMinutes - reference.partialSemiDurationMinutes)
                    <= reference.durationToleranceMinutes)
            #expect(
                abs(actual.totalDurationMinutes - reference.totalSemiDurationMinutes)
                    <= reference.durationToleranceMinutes)
            var measurement: [String: Any] = [
                "sourceTime": reference.universalTime,
                "kind": actual.kind.rawValue,
                "nativePeakTT": actual.peak.tt,
                "peakResidualSeconds": peakResidual,
                "penumbralDurationMinutes": actual.penumbralDurationMinutes,
                "partialDurationMinutes": actual.partialDurationMinutes,
                "totalDurationMinutes": actual.totalDurationMinutes,
                "obscuration": actual.obscuration,
            ]
            if let expectedDuration = reference.penumbralSemiDurationMinutes {
                measurement["penumbralDurationResidualMinutes"] =
                    abs(actual.penumbralDurationMinutes - expectedDuration)
            }
            measurements.append(measurement)
        }
        try Self.write(measurements, name: "published")
    }

    @Test("NASA lunar obscuration retains the published Moon-disc area")
    func publishedLunarObscuration() throws {
        var measurements: [[String: Any]] = []
        for reference in IndependentReferenceArchive.shared.lunarEclipseObscurations {
            let seed = IndependentReferenceDate.engine(reference.universalTimeSearchSeed)
            let actual = try Events.searchLunarEclipse(after: seed.adding(days: -10))
            #expect(actual.kind == .partial)
            #expect(actual.obscuration >= reference.roundingLowerBound)
            #expect(actual.obscuration <= reference.roundingUpperBound)
            measurements.append([
                "sourceTimeSearchSeed": reference.universalTimeSearchSeed,
                "nativePeakTT": actual.peak.tt,
                "obscuration": actual.obscuration,
            ])
        }
        try Self.write(measurements, name: "obscurations")
    }

    @Test("Lunar search includes an eclipse after its full-moon boundary and excludes it after peak")
    func lunarEclipseStartBoundary() throws {
        let nearJanuaryPeak = IndependentReferenceDate.engine("2000-01-21T04:42:00Z")
        let fullMoon = try #require(
            try Events.searchMoonPhase(180, after: nearJanuaryPeak.adding(days: -1), limitDays: 2))
        let second = 1 / Engine.secondsPerDay
        let january = try Events.searchLunarEclipse(after: fullMoon.adding(days: -second))
        #expect(fullMoon.tt < january.peak.tt)

        for start in [
            fullMoon,
            fullMoon.adding(days: second),
            january.peak.adding(days: -second),
            january.peak,
        ] {
            let result = try Events.searchLunarEclipse(after: start)
            #expect(
                abs(result.peak.tt - january.peak.tt) * Engine.secondsPerDay <= 1,
                "search start TT \(start.tt)")
            #expect(result.peak.tt >= start.tt)
        }

        let later = try Events.searchLunarEclipse(after: january.peak.adding(days: second))
        #expect(later.peak.tt > january.peak.tt)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["ECLIPSE_EVENT_MEASUREMENT"] != nil))
    func resources() throws {
        func peakBytes() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1_024
            #endif
        }

        let start = IndependentReferenceDate.engine("1900-01-01T00:00:00Z")
        let before = peakBytes()
        let coldStart = Date()
        var eclipse = try Events.searchLunarEclipse(after: start)
        let coldSeconds = Date().timeIntervalSince(coldStart)
        let afterCold = peakBytes()
        var checksum = eclipse.peak.tt
        let workloadStart = Date()
        for _ in 1..<100 {
            eclipse = try Events.nextLunarEclipse(after: eclipse)
            checksum += eclipse.peak.tt + eclipse.obscuration
        }
        try Self.write(
            [
                "coldSeconds": coldSeconds,
                "nextEclipseCount": 99,
                "nextEclipsesSeconds": Date().timeIntervalSince(workloadStart),
                "totalEclipseCount": 100,
                "peakBeforeBytes": before,
                "peakAfterColdBytes": afterCold,
                "peakAfterWorkloadBytes": peakBytes(),
                "checksum": checksum,
                "host": ProcessInfo.processInfo.operatingSystemVersionString,
            ], name: "resources")
    }

    @Test("Consecutive eclipses advance, preserve the model, and include penumbral events")
    func consecutiveLunarEclipses() throws {
        let start = Engine.Time(
            ut: IndependentReferenceDate.universal("2001-01-01T00:00:00Z", deltaTModel: .jplHorizons).universalTime,
            deltaTModel: .jplHorizons)
        let first = try Events.searchLunarEclipse(after: start)
        let second = try Events.nextLunarEclipse(after: first)
        let third = try Events.nextLunarEclipse(after: second)
        #expect([first.kind, second.kind, third.kind] == [.total, .partial, .penumbral])
        #expect(first.peak.tt < second.peak.tt && second.peak.tt < third.peak.tt)
        #expect([first.peak, second.peak, third.peak].allSatisfy { $0.deltaTModel == .jplHorizons })
    }

    @Test("Lunar eclipse search rejects unsupported and nonfinite times")
    func lunarEclipseRange() throws {
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchLunarEclipse(after: .invalid) }
        let nearEnd = Engine.Time(tt: Engine.acceptedTTDays - 1, deltaTModel: .espenakMeeus)
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchLunarEclipse(after: nearEnd) }
        let nearStart = Engine.Time(tt: -Engine.acceptedTTDays + 1, deltaTModel: .jplHorizons)
        let firstSupported = try Events.searchLunarEclipse(after: nearStart)
        #expect(firstSupported.peak.tt >= nearStart.tt)
        #expect(firstSupported.peak.deltaTModel == .jplHorizons)
        let lowerEndpoint = Engine.Time(tt: -Engine.acceptedTTDays, deltaTModel: .espenakMeeus)
        #expect(try Events.searchLunarEclipse(after: lowerEndpoint).peak.tt >= lowerEndpoint.tt)
    }
}

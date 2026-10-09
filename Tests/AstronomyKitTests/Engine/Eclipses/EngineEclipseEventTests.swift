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
        let peakModel = try #require(january.peak.deltaTModel)
        let firstRepresentableTTAfterPeak = Engine.Time(tt: january.peak.tt.nextUp, deltaTModel: peakModel)

        for start in [
            fullMoon,
            fullMoon.adding(days: second),
            january.peak.adding(days: -second),
            january.peak,
            firstRepresentableTTAfterPeak,
        ] {
            let result = try Events.searchLunarEclipse(after: start)
            #expect(
                abs(result.peak.tt - january.peak.tt) * Engine.secondsPerDay <= 1,
                "search start TT \(start.tt)")
            #expect(result.peak.tt >= start.tt)
        }

        let resolutionStart = Engine.Time(tt: january.peak.tt + second, deltaTModel: peakModel)
        let atResolution = try Events.searchLunarEclipse(after: resolutionStart)
        #expect(atResolution.peak.tt == resolutionStart.tt)
        #expect(atResolution.kind == january.kind)

        let later = try Events.searchLunarEclipse(after: january.peak.adding(days: 2 * second))
        #expect(later.peak.tt > january.peak.tt)
    }

    @Test("Lunar peak resolution defines the inclusive search boundary")
    func lunarEclipsePeakResolutionBoundary() throws {
        let model = DeltaTModel.espenakMeeus
        let peak = Engine.Time(tt: 0, deltaTModel: model)
        let eclipse = Events.LunarEclipse(
            kind: .partial, peak: peak, obscuration: 0.5, penumbralDurationMinutes: 90,
            partialDurationMinutes: 45, totalDurationMinutes: 0)
        let resolutionDays = Events.peakSearchResolutionSeconds / Engine.secondsPerDay
        let resolutionBoundaryTT = peak.tt + resolutionDays
        let acceptedStarts = [
            peak,
            Engine.Time(tt: peak.tt.nextUp, deltaTModel: model),
            Engine.Time(tt: resolutionBoundaryTT.nextDown, deltaTModel: model),
            Engine.Time(tt: resolutionBoundaryTT, deltaTModel: model),
        ]

        for start in acceptedStarts {
            let accepted = try #require(Events.resolvedLunarEclipse(eclipse, atOrAfter: start))
            #expect(accepted.peak.tt == max(peak.tt, start.tt))
            #expect(accepted.peak.deltaTModel == model)
            #expect(accepted.kind == eclipse.kind)
            #expect(accepted.obscuration == eclipse.obscuration)
            #expect(accepted.penumbralDurationMinutes == eclipse.penumbralDurationMinutes)
            #expect(accepted.partialDurationMinutes == eclipse.partialDurationMinutes)
            #expect(accepted.totalDurationMinutes == eclipse.totalDurationMinutes)
        }

        let afterResolution = Engine.Time(tt: resolutionBoundaryTT.nextUp, deltaTModel: model)
        #expect(Events.resolvedLunarEclipse(eclipse, atOrAfter: afterResolution) == nil)
    }

    @Test("Lunar eclipse identity does not depend on the discovery start")
    func lunarEclipseCanonicalIdentity() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            let starts = [18.0, 19.0, 19.5, 19.69]
            let events = try starts.map {
                try Events.searchLunarEclipse(after: Engine.Time(tt: $0, deltaTModel: model))
            }
            let first = try #require(events.first)
            for event in events {
                #expect(event.peak.tt.bitPattern == first.peak.tt.bitPattern)
                #expect(event.peak.ut.bitPattern == first.peak.ut.bitPattern)
                #expect(event.obscuration == first.obscuration)
                #expect(event.penumbralDurationMinutes == first.penumbralDurationMinutes)
                #expect(event.partialDurationMinutes == first.partialDurationMinutes)
                #expect(event.totalDurationMinutes == first.totalDurationMinutes)
            }
        }
    }

    @Test("Lunar cutoff uses a represented endpoint and cannot advance through repeated clamps")
    func lunarEclipseRepresentedCutoff() throws {
        let second = 1 / Engine.secondsPerDay
        for peakTT in [19.69759754046248, 197.08098727024625, -1_460_999.0, 1_460_999.0] {
            let peak = Engine.Time(tt: peakTT, deltaTModel: .espenakMeeus)
            let eclipse = Events.LunarEclipse(
                kind: .partial, peak: peak, obscuration: 0.5, penumbralDurationMinutes: 90,
                partialDurationMinutes: 45, totalDurationMinutes: 0)
            let cutoff = peakTT + second
            for startTT in [cutoff.nextDown, cutoff] {
                let start = Engine.Time(tt: startTT, deltaTModel: .espenakMeeus)
                let accepted = try #require(Events.resolvedLunarEclipse(eclipse, atOrAfter: start))
                #expect(accepted.peak.tt == startTT)
                let excluded = Engine.Time(tt: cutoff.nextUp, deltaTModel: .espenakMeeus)
                #expect(Events.resolvedLunarEclipse(accepted, atOrAfter: excluded) == nil)
                #expect(Events.resolvedLunarEclipse(eclipse, atOrAfter: excluded) == nil)
            }
        }
    }

    @Test("Canonical lunar phase brackets retain identity across midnight and exact zeros")
    func canonicalLunarPhaseBrackets() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            for seed in [19.0, 197.0, 550.0, 7_993.0, 9_735.0] {
                let phase = try #require(
                    try Events.searchMoonPhase(180, after: Engine.Time(tt: seed - 2, deltaTModel: model), limitDays: 40)
                )
                let expected = try Events.canonicalFullMoon(phase)
                let midnight = floor(phase.tt)
                for candidateTT in [
                    phase.tt - 0.9 / Engine.secondsPerDay, phase.tt, phase.tt + 0.9 / Engine.secondsPerDay,
                    midnight.nextDown, midnight.nextUp,
                ] {
                    let actual = try Events.canonicalFullMoon(Engine.Time(tt: candidateTT, deltaTModel: model))
                    #expect(actual.tt.bitPattern == expected.tt.bitPattern)
                    #expect(actual.ut.bitPattern == expected.ut.bitPattern)
                    #expect(actual.deltaTModel == model)
                }
            }
            for rootTT in [-Engine.acceptedTTDays, 20.0, Engine.acceptedTTDays] {
                for candidateTT in [rootTT.nextDown, rootTT, rootTT.nextUp]
                where abs(candidateTT) <= Engine.acceptedTTDays {
                    let actual = try Events.canonicalFullMoon(Engine.Time(tt: candidateTT, deltaTModel: model)) {
                        #expect(abs($0.tt) <= Engine.acceptedTTDays)
                        return $0.tt - rootTT
                    }
                    #expect(actual.tt == rootTT)
                    #expect(actual.deltaTModel == model)
                }
            }
        }
    }

    @Test("Canonical phase failures remain bounded and preserve input and callback errors")
    func canonicalLunarPhaseErrors() throws {
        let valid = Engine.Time(tt: 19, deltaTModel: .espenakMeeus)
        var evaluations = 0
        #expect(throws: AstronomyError.searchFailure) {
            _ = try Events.canonicalFullMoon(valid) { _ in
                evaluations += 1
                return 1
            }
        }
        #expect(evaluations == 6)
        #expect(throws: AstronomyError.badTime) {
            _ = try Events.canonicalFullMoon(valid) { _ in .nan }
        }
        #expect(throws: AstronomyError.noConvergence) {
            _ = try Events.canonicalFullMoon(valid) { _ in throw AstronomyError.noConvergence }
        }
        for invalid in [Engine.Time.invalid, Engine.Time(tt: Engine.acceptedTTDays.nextUp, deltaTModel: .espenakMeeus)]
        {
            #expect(throws: AstronomyError.badTime) {
                _ = try Events.canonicalFullMoon(invalid) { _ in
                    Issue.record("Invalid candidate evaluated the phase callback")
                    return 0
                }
            }
        }
    }

    @Test("Repeated eclipse presentation clamps retain the physical cutoff and contacts")
    func lunarEclipseClampedSearchBoundary() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            let first = try Events.searchLunarEclipse(after: Engine.Time(tt: 19, deltaTModel: model))
            let cutoff = first.peak.tt + 1 / Engine.secondsPerDay
            for startTT in [cutoff.nextDown, cutoff] {
                let start = Engine.Time(tt: startTT, deltaTModel: model)
                let event = try Events.searchLunarEclipse(after: start)
                #expect(event.peak.tt == startTT)
                #expect(event.physicalPeak.tt == first.physicalPeak.tt)
                #expect(event.obscuration == first.obscuration)
                #expect(event.kind == first.kind)
                #expect(event.penumbralDurationMinutes == first.penumbralDurationMinutes)
                #expect(event.partialDurationMinutes == first.partialDurationMinutes)
                #expect(event.totalDurationMinutes == first.totalDurationMinutes)
                #expect(event.peak.deltaTModel == model)
                let repeated = try Events.searchLunarEclipse(after: event.peak)
                #expect(repeated.peak.tt == event.peak.tt)
                #expect(repeated.physicalPeak.tt == first.physicalPeak.tt)
                let outside = Engine.Time(tt: cutoff.nextUp, deltaTModel: model)
                #expect(Events.resolvedLunarEclipse(event, atOrAfter: outside) == nil)
                let next = try Events.nextLunarEclipse(after: event)
                #expect(next.peak.tt > cutoff)
                #expect(next.peak.deltaTModel == model)
            }
            let excluded = try Events.searchLunarEclipse(after: Engine.Time(tt: cutoff.nextUp, deltaTModel: model))
            #expect(excluded.physicalPeak.tt > cutoff)
        }
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

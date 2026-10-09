import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Events planetary searches")
struct EnginePlanetaryEventTests {
    typealias Events = Engine.Events

    static let planets: [CelestialBody] = [
        .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
    ]

    static func time(_ utc: String, model: DeltaTModel = .espenakMeeus) -> Engine.Time {
        Engine.Time(ut: IndependentReferenceDate.universal(utc, deltaTModel: model).universalTime, deltaTModel: model)
    }

    static func write(_ value: Any, environment: String) throws {
        guard let path = ProcessInfo.processInfo.environment[environment] else { return }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: path))
    }

    @Test("Published Mercury and Venus maximum-elongation brackets")
    func publishedMaximumElongations() throws {
        for reference in IndependentReferenceArchive.shared.maximumElongationEvents {
            let body: CelestialBody = reference.body == "mercury" ? .mercury : .venus
            let event = try Events.searchMaximumElongation(of: body, after: Self.time(reference.startUTC))
            let lower = Self.time(reference.lowerUTC)
            let upper = Self.time(reference.upperUTC)
            #expect(event.time.tt >= lower.tt && event.time.tt <= upper.tt, "\(reference.body) \(reference.sampleUTC)")
            #expect(abs(event.elongation - reference.sampledMaximumDegrees) <= reference.angleToleranceDegrees)
            #expect(event.visibility == (reference.trailsSun ? .evening : .morning))
        }
    }

    @Test("Venus peak magnitude falls inside a published APmag minimum interval")
    func publishedPeakMagnitude() throws {
        let start = Self.time("2025-02-01T00:00:00Z", model: .jplHorizons)
        let rows = try EngineIlluminationTests.magnitudeRows(.venus).filter {
            $0.label.contains("2025-Feb")
        }
        let sourceMinimum = try #require(rows.map(\.magnitude).min())
        let minimumRows = rows.filter { $0.magnitude == sourceMinimum }
        let lower = try #require(minimumRows.first).time
        let upper = try #require(minimumRows.last).time.adding(days: 2)
        let event = try Events.searchPeakMagnitude(of: .venus, after: start)
        #expect(event.time.tt >= lower.tt && event.time.tt <= upper.tt)
        #expect(abs(event.magnitude - sourceMinimum) <= 0.012)
        #expect(event.time.deltaTModel == .jplHorizons)
    }

    @Test("Published Earth apsides retain kind, civil time, and distance allowances")
    func publishedEarthApsides() throws {
        for reference in IndependentReferenceArchive.shared.earthApsides {
            let expected = Engine.Time(
                tt: IndependentReferenceDate.civil(reference.utc).terrestrialTime, deltaTModel: .espenakMeeus)
            let event = try Events.searchPlanetaryApsis(of: .earth, after: expected.adding(days: -30))
            #expect(event.kind == (reference.kind == "pericenter" ? .pericenter : .apocenter))
            #expect(abs(event.time.tt - expected.tt) * Engine.secondsPerDay <= reference.timeToleranceSeconds)
            #expect(
                abs(event.distanceAU - (try #require(reference.distanceAU)))
                    <= (try #require(reference.distanceToleranceAU)))
        }
    }

    @Test("Saturn body-center references meet the unchanged sixty-second target")
    func saturnBodyCenterApsides() throws {
        let references = IndependentReferenceArchive.shared.saturnApsides
        #expect(references.count == 6)
        var measurements: [[String: Any]] = []
        for reference in references {
            #expect(reference.body == "saturn")
            #expect(reference.sourceToleranceSeconds == 1)
            #expect(reference.acceptanceToleranceSeconds == 60)
            let expected = Engine.Time(
                tt: reference.julianDateTT - 2_451_545,
                deltaTModel: .jplHorizons)
            let event = try Events.searchPlanetaryApsis(
                of: .saturn,
                after: expected.adding(days: -30))
            #expect(event.kind == (reference.kind == "pericenter" ? .pericenter : .apocenter))
            let signedError = (event.time.tt - expected.tt) * Engine.secondsPerDay
            let error = abs(signedError)
            func nativeSlope(_ time: Engine.Time) throws -> Double {
                let first = try Engine.Positions.heliocentricDistance(
                    of: .saturn,
                    at: time.adding(days: -0.0005))
                let second = try Engine.Positions.heliocentricDistance(
                    of: .saturn,
                    at: time.adding(days: 0.0005))
                return (second - first) / 0.001
            }
            let nativeDistanceAtReference = try Engine.Positions.heliocentricDistance(of: .saturn, at: expected)
            measurements.append([
                "referenceJulianDateTT": reference.julianDateTT,
                "nativeJulianDateTT": event.time.tt + 2_451_545,
                "signedTimingErrorSeconds": signedError,
                "sourceRangeRateAUPerDay": reference.sourceRangeRateAUPerDay,
                "nativeSlopeAtReferenceAUPerDay": try nativeSlope(expected),
                "nativeSlopeAtEventAUPerDay": try nativeSlope(event.time),
                "nativeMinusSourceDistanceAUAtReference": nativeDistanceAtReference - reference.distanceAU,
            ])
            #expect(error < reference.acceptanceToleranceSeconds, "\(reference.julianDateTT): \(error) s")
        }
        try Self.write(measurements, environment: "SATURN_APSIS_EVIDENCE_OUTPUT")
    }

    @Test("Frozen physical-center source brackets expose remaining planetary timing gaps")
    func sourceApsisBrackets() throws {
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
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let archive = try JSONDecoder().decode(
            Archive.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/reference-data/planetary-apsis-evidence.json")))
        #expect(archive.cases.count == 8)
        var measurements: [[String: Any]] = []
        for reference in archive.cases {
            let body = try #require(Self.planets.first { $0.name.lowercased() == reference.body })
            let start = Self.time("2025-01-01T00:00:00Z", model: .espenakMeeus)
            let event = try Events.searchPlanetaryApsis(of: body, after: start)
            let jd = event.time.tt + 2_451_545
            let kind = event.kind == .pericenter ? "pericenter" : "apocenter"
            let matching = reference.roots.filter { $0.kind == kind }
            let nearest = try #require(
                matching.min {
                    abs(jd - ($0.lowerJDTT + $0.upperJDTT) / 2) < abs(jd - ($1.lowerJDTT + $1.upperJDTT) / 2)
                })
            #expect((nearest.upperJDTT - nearest.lowerJDTT) * Engine.secondsPerDay <= 1)
            let seconds = (jd - (nearest.lowerJDTT + nearest.upperJDTT) / 2) * Engine.secondsPerDay
            let original = try body.searchApsis(
                after: AstroTime(tt: start.tt, ut: start.ut, deltaTModel: .espenakMeeus))
            measurements.append([
                "body": reference.body, "nativeJDTT": jd, "sourceLowerJDTT": nearest.lowerJDTT,
                "sourceUpperJDTT": nearest.upperJDTT, "nativeMinusSourceSeconds": seconds,
                "publicCMinusSourceSeconds":
                    (original.time.terrestrialTime + 2_451_545 - (nearest.lowerJDTT + nearest.upperJDTT) / 2)
                    * Engine.secondsPerDay,
                "localCrossings": reference.roots.count,
            ])
            if [.jupiter, .uranus, .neptune].contains(body) {
                withKnownIssue(
                    "#92: retained outer-planet trajectories do not meet the physical-center sixty-second target; local crossings do not identify an orbit's principal extremum"
                ) {
                    #expect(abs(seconds) < 60, "\(body): \(seconds) s")
                }
            } else {
                #expect(abs(seconds) < 60, "\(body): \(seconds) s")
            }
        }
        try Self.write(measurements, environment: "PLANETARY_SOURCE_EVIDENCE_OUTPUT")
    }

    @Test("Every planet returns an ordered alternating sequence on its native trajectory", arguments: planets)
    func supportedPlanetApsides(body: CelestialBody) throws {
        let start = Self.time("2025-01-01T00:00:00Z", model: .jplHorizons)
        let first = try Events.searchPlanetaryApsis(of: body, after: start)
        let second = try Events.nextPlanetaryApsis(of: body, after: first)
        #expect(first.time.tt >= start.tt)
        #expect(second.time.tt > first.time.tt)
        #expect(second.kind != first.kind)
        #expect(first.time.deltaTModel == .jplHorizons && second.time.deltaTModel == .jplHorizons)
        #expect(first.distanceAU == (try Engine.Positions.heliocentricDistance(of: body, at: first.time)))
        #expect(second.distanceAU == (try Engine.Positions.heliocentricDistance(of: body, at: second.time)))
    }

    @Test("Elongation and peak searches preserve direction and reject unsupported bodies")
    func visibilityContracts() throws {
        let start = Self.time("2025-01-01T00:00:00Z", model: .jplHorizons)
        for body: CelestialBody in [.mercury, .venus] {
            let event = try Events.searchMaximumElongation(of: body, after: start)
            #expect(event.time.tt >= start.tt && event.time.deltaTModel == .jplHorizons)
        }
        let peak = try Events.searchPeakMagnitude(of: .venus, after: start)
        #expect(peak.time.tt >= start.tt && peak.time.deltaTModel == .jplHorizons)
        #expect(throws: AstronomyError.invalidBody) { _ = try Events.searchMaximumElongation(of: .mars, after: start) }
        #expect(throws: AstronomyError.invalidBody) { _ = try Events.searchPeakMagnitude(of: .mercury, after: start) }
    }

    @Test("Unchanged trajectories retain the original search classifications and times")
    func originalAlgorithmParity() throws {
        let start = Self.time("2025-01-01T00:00:00Z", model: .espenakMeeus)
        let publicStart = AstroTime(tt: start.tt, ut: start.ut, deltaTModel: .espenakMeeus)
        var maximumElongationSeconds = 0.0
        for body: CelestialBody in [.mercury, .venus] {
            let native = try Events.searchMaximumElongation(of: body, after: start)
            let original = try body.searchMaxElongation(after: publicStart)
            let seconds = abs(native.time.tt - original.time.terrestrialTime) * Engine.secondsPerDay
            maximumElongationSeconds = max(maximumElongationSeconds, seconds)
            #expect(seconds < 10)
            #expect(native.visibility == original.visibility)
        }
        let nativePeak = try Events.searchPeakMagnitude(of: .venus, after: start)
        let originalPeak = try CelestialBody.venus.searchPeakMagnitude(after: publicStart)
        let peakSeconds = abs(nativePeak.time.tt - originalPeak.time.terrestrialTime) * Engine.secondsPerDay
        #expect(peakSeconds < 10)
        #expect(abs(nativePeak.magnitude - originalPeak.magnitude) < 1e-9)
        var maximumApsisSeconds = 0.0
        var worstApsisBody = ""
        var apsisEvents: [[String: Any]] = []
        for body in Self.planets where ![.saturn, .neptune, .pluto].contains(body) {
            let native = try Events.searchPlanetaryApsis(of: body, after: start)
            let original = try body.searchApsis(after: publicStart)
            apsisEvents.append([
                "body": body.name.lowercased(), "jdtt": native.time.tt + 2_451_545,
                "kind": native.kind == .pericenter ? "pericenter" : "apocenter",
            ])
            let seconds = abs(native.time.tt - original.time.terrestrialTime) * Engine.secondsPerDay
            if seconds > maximumApsisSeconds {
                maximumApsisSeconds = seconds
                worstApsisBody = body.name
            }
            #expect(seconds < 60, "\(body)")
            #expect((native.kind == .pericenter) == (original.kind == .pericenter), "\(body)")
        }
        try Self.write(
            [
                "maximumElongationParitySeconds": maximumElongationSeconds,
                "peakMagnitudeParitySeconds": peakSeconds,
                "planetaryApsisParitySeconds": maximumApsisSeconds,
                "planetaryApsisWorstBody": worstApsisBody,
                "planetaryApsisBodies": Self.planets.count - 3,
                "apsisEvents": apsisEvents,
            ], environment: "PLANETARY_EVENT_EVIDENCE_OUTPUT")
    }

    @Test("Planetary searches reject invalid times, unsupported bodies, and out-of-source windows")
    func invalidInputs() {
        #expect(throws: AstronomyError.badTime) {
            _ = try Events.searchMaximumElongation(of: .mercury, after: .invalid)
        }
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchPeakMagnitude(of: .venus, after: .invalid) }
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchPlanetaryApsis(of: .mars, after: .invalid) }
        for body in CelestialBody.allCases where !Self.planets.contains(body) {
            #expect(throws: AstronomyError.invalidBody, "\(body)") {
                _ = try Events.searchPlanetaryApsis(of: body, after: Self.time("2025-01-01T00:00:00Z"))
            }
        }
        let plutoEnd = Engine.Time(tt: Engine.PlutoDE441.acceptedTTDays, deltaTModel: .jplHorizons)
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchPlanetaryApsis(of: .pluto, after: plutoEnd) }
    }
}

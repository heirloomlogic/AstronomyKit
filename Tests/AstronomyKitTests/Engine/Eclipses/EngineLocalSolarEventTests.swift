import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Native local solar eclipses")
struct EngineLocalSolarEventTests {
    typealias Events = Engine.Events
    static func write(_ value: Any, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["LOCAL_SOLAR_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
            to: url.appendingPathComponent(name + ".json"))
    }

    @Test("Inherited map timestamps identify publisher UT1, despite legacy UTC field names")
    func sourceEpoch() throws {
        let provenance = try #require(IndependentReferenceArchive.shared.provenance["eclipseWiseLocalSolar"])
        #expect(provenance.timeScale.contains("UT1"))
        let time = IndependentReferenceDate.universal("2024-04-08T19:04:48Z", deltaTModel: .espenakMeeus)
        #expect(time.universalTime == 8864.295)
        #expect(
            abs(time.universalTime - IndependentReferenceDate.civil("2024-04-08T19:04:48Z").universalTime) * 86400 > 1)
    }

    @Test("Published local contact kinds, UT1 times and altitudes")
    func published() throws {
        var rows: [[String: Any]] = []
        for row in IndependentReferenceArchive.shared.localSolarEclipses {
            let expected = IndependentReferenceDate.universal(row.peakUTC, deltaTModel: .espenakMeeus)
            let site = Observer(latitude: row.latitudeDegrees, longitude: row.longitudeDegrees)
            let eclipse = try Engine.Events.searchLocalSolarEclipse(
                after: Engine.Time(tt: expected.terrestrialTime - 10, deltaTModel: .espenakMeeus), from: site)
            #expect(eclipse.kind.rawValue == row.kind)
            #expect(abs(eclipse.peak.time.tt - expected.terrestrialTime) * 86400 <= row.timeToleranceSeconds)
            #expect(eclipse.partialBegin.time.tt < eclipse.peak.time.tt)
            #expect(eclipse.peak.time.tt < eclipse.partialEnd.time.tt)
            #expect((eclipse.totalBegin != nil) == (row.totalBeginUTC != nil))
            var contacts: [[String: Any]] = []
            func check(
                _ label: String, _ actual: Events.LocalSolarContact?, _ source: String?, _ altitude: Double?
            ) throws {
                guard let source, let altitude else {
                    #expect(actual == nil)
                    return
                }
                let actual = try #require(actual)
                let expected = IndependentReferenceDate.universal(source, deltaTModel: .espenakMeeus)
                #expect(abs(actual.time.ut - expected.universalTime) * 86400 <= row.timeToleranceSeconds)
                if altitude >= 0 { #expect(abs(actual.altitude - altitude) <= row.altitudeToleranceDegrees) }
                contacts.append([
                    "name": label, "source": source, "sourceUT": expected.universalTime, "ut": actual.time.ut,
                    "tt": actual.time.tt, "altitude": actual.altitude,
                    "formerUTCResidualSeconds": (actual.time.ut - IndependentReferenceDate.civil(source).universalTime)
                        * 86400,
                ])
            }
            try check("partialBegin", eclipse.partialBegin, row.partialBeginUTC, row.partialBeginAltitudeDegrees)
            try check("totalBegin", eclipse.totalBegin, row.totalBeginUTC, row.totalBeginAltitudeDegrees)
            try check("peak", eclipse.peak, row.peakUTC, row.peakAltitudeDegrees)
            try check("totalEnd", eclipse.totalEnd, row.totalEndUTC, row.totalEndAltitudeDegrees)
            try check("partialEnd", eclipse.partialEnd, row.partialEndUTC, row.partialEndAltitudeDegrees)
            rows.append([
                "latitude": row.latitudeDegrees, "longitude": row.longitudeDegrees, "kind": eclipse.kind.rawValue,
                "obscuration": eclipse.obscuration, "physicalTT": eclipse.physicalPeak.tt, "contacts": contacts,
            ])
        }
        try Self.write(rows, name: "published")
    }
    struct References: Decodable {
        let events: [Reference]
        let sequence: Sequence
        struct Sequence: Decodable {
            let latitude: Double
            let longitude: Double
            let events: [SequenceEvent]
        }
        struct SequenceEvent: Decodable {
            let date: String
            let localKind: String
            let gmtCalendarDays: [String: Double]
        }
        struct Reference: Decodable {
            let id: String
            let latitude: Double
            let longitude: Double
            let heightMeters: Double
            let kind: String
            let contacts: [Contact]
            let lower: Double
            let upper: Double
            let timeToleranceSeconds: Double
            let altitudeToleranceDegrees: Double
        }
        struct Contact: Decodable {
            let name: String
            let ut: Double
            let tt: Double
            let altitude: Double
        }
    }

    @Test("RP1301 local contacts and directly printed partial/annular area")
    func report() throws {
        let references = try JSONDecoder().decode(
            References.self,
            from: Data(
                contentsOf: EngineGlobalSolarEventTests.root.appendingPathComponent(
                    "Scripts/eclipse-data/local-references.json")))
        var rows: [[String: Any]] = []
        for row in references.events {
            let peak = try #require(row.contacts.first { $0.name == "peak" })
            let observer = Observer(latitude: row.latitude, longitude: row.longitude, height: row.heightMeters)
            let event = try Events.searchLocalSolarEclipse(
                after: Engine.Time(tt: peak.tt - 10, deltaTModel: .espenakMeeus), from: observer)
            #expect(event.kind.rawValue == row.kind)
            let sourceTime = Engine.Time(tt: peak.tt, deltaTModel: .espenakMeeus)
            let geometry = try Events.localSolarGeometry(at: sourceTime, from: observer)
            #expect(geometry.discs.obscuration >= row.lower && geometry.discs.obscuration <= row.upper)
            #expect(abs(sourceTime.adding(days: 0).tt - sourceTime.tt) < 1e-10)
            var contacts: [[String: Any]] = []
            let values = [
                "partialBegin": event.partialBegin, "totalBegin": event.totalBegin, "peak": event.peak,
                "totalEnd": event.totalEnd, "partialEnd": event.partialEnd,
            ]
            for source in row.contacts {
                let actual = try #require(values[source.name] ?? nil)
                #expect(abs(actual.time.ut - source.ut) * 86400 <= row.timeToleranceSeconds)
                #expect(abs(actual.altitude - source.altitude) <= row.altitudeToleranceDegrees)
                contacts.append([
                    "name": source.name, "sourceUT": source.ut, "sourceTT": source.tt, "ut": actual.time.ut,
                    "tt": actual.time.tt, "altitude": actual.altitude,
                ])
            }
            rows.append([
                "id": row.id, "kind": event.kind.rawValue, "contacts": contacts, "obscuration": event.obscuration,
                "sourceEpochObscuration": geometry.discs.obscuration, "sourceTT": sourceTime.tt,
                "modelUT": sourceTime.ut, "sourceUT": peak.ut, "sunRadius": geometry.discs.sunRadiusRadians,
                "moonRadius": geometry.discs.moonRadiusRadians, "separation": geometry.discs.separationRadians,
            ])
        }
        try Self.write(rows, name: "report")
    }

    @Test("Local canonical identity, inclusive cutoff, clamps, models and next progress")
    func identity() throws {
        let site = Observer(latitude: 41.0341, longitude: -83.6523)
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            let event = try Events.searchLocalSolarEclipse(after: Engine.Time(tt: 8860, deltaTModel: model), from: site)
            let cutoff = event.physicalPeak.tt + 1 / Engine.secondsPerDay
            for tt in [event.physicalPeak.tt - 0.1 / 86400, event.physicalPeak.tt, cutoff.nextDown, cutoff] {
                let repeated = try Events.searchLocalSolarEclipse(
                    after: Engine.Time(tt: tt, deltaTModel: model), from: site)
                #expect(repeated.physicalPeak.tt.bitPattern == event.physicalPeak.tt.bitPattern)
                #expect(repeated.peak.time.tt >= tt)
                #expect(repeated.kind == event.kind && repeated.obscuration == event.obscuration)
                #expect(repeated.partialBegin.time.tt == event.partialBegin.time.tt)
                #expect(repeated.totalEnd?.time.tt == event.totalEnd?.time.tt)
                #expect(repeated.peak.time.deltaTModel == model)
            }
            #expect(
                try Events.resolvedLocalSolarEclipse(
                    event, atOrAfter: Engine.Time(tt: cutoff.nextUp, deltaTModel: model), from: site) == nil)
            var clamped = event
            for step in [0.25, 0.5, 0.75, 1.0] {
                clamped = try #require(
                    try Events.resolvedLocalSolarEclipse(
                        clamped, atOrAfter: Engine.Time(tt: event.physicalPeak.tt + step / 86400, deltaTModel: model),
                        from: site))
                #expect(clamped.physicalPeak.tt == event.physicalPeak.tt)
            }
            #expect(
                try Events.resolvedLocalSolarEclipse(
                    clamped, atOrAfter: Engine.Time(tt: cutoff.nextUp, deltaTModel: model), from: site) == nil)
            let next = try Events.nextLocalSolarEclipse(after: event, from: site)
            let excluded = try Events.searchLocalSolarEclipse(
                after: Engine.Time(tt: event.physicalPeak.tt + 2 / 86400, deltaTModel: model), from: site)
            #expect(next.physicalPeak.tt == excluded.physicalPeak.tt)
            let outside = try Events.searchLocalSolarEclipse(
                after: Engine.Time(tt: cutoff.nextUp, deltaTModel: model), from: site)
            #expect(outside.physicalPeak.tt == next.physicalPeak.tt)
            #expect(next.physicalPeak.tt > event.physicalPeak.tt + 10)
            #expect(next.peak.time.deltaTModel == model)
        }
    }

    @Test("Contact roots bracket overlap changes without a limb epsilon")
    func contacts() throws {
        for row in IndependentReferenceArchive.shared.localSolarEclipses {
            let observer = Observer(latitude: row.latitudeDegrees, longitude: row.longitudeDegrees)
            let time = IndependentReferenceDate.engine(row.peakUTC)
            let event = try Events.searchLocalSolarEclipse(after: time.adding(days: -10), from: observer)
            for (contact, interior, rising) in [
                (event.partialBegin, false, true), (event.partialEnd, false, false), (event.totalBegin, true, true),
                (event.totalEnd, true, false),
            ] {
                guard let contact else { continue }
                let before = try Events.localSolarGeometry(at: contact.time.adding(days: -2 / 86400), from: observer)
                let after = try Events.localSolarGeometry(at: contact.time.adding(days: 2 / 86400), from: observer)
                let first = interior ? before.interiorMargin : before.exteriorMargin
                let last = interior ? after.interiorMargin : after.exteriorMargin
                #expect(rising ? first < 0 && last > 0 : first > 0 && last < 0)
            }
            #expect(event.isVisible)
            #expect(event.obscuration > 0 && event.obscuration <= 1)
            if event.kind == .total { #expect(event.obscuration == 1) }
        }
    }

    @Test("Local candidates distinguish misses, below-horizon geometry and polar observers")
    func visibility() throws {
        let phase = try Events.canonicalNewMoon(
            try #require(
                try Events.searchMoonPhase(0, after: Engine.Time(tt: 8860, deltaTModel: .espenakMeeus), limitDays: 10)))
        var invisible = 0
        var misses = 0
        for latitude in [-90.0, -45, 0, 45, 90] {
            for longitude in [-180.0, -90, 0, 90] {
                let site = Observer(latitude: latitude, longitude: longitude)
                if let event = try Events.localSolarEclipse(near: phase, from: site) {
                    #expect(event.peak.altitude.isFinite)
                    if !event.isVisible { invisible += 1 }
                } else {
                    misses += 1
                }
            }
        }
        #expect(invisible > 0 && misses > 0)
        let settingSite = Observer(latitude: 4.6622, longitude: 170.8101)
        let event = try Events.searchLocalSolarEclipse(
            after: Engine.Time(tt: 8500, deltaTModel: .espenakMeeus), from: settingSite)
        #expect(event.partialBegin.isVisible && !event.partialEnd.isVisible)
        #expect(event.isVisible && event.kind == .partial)
    }

    @Test("Local invalid observers, epochs, failed brackets and domain edges throw")
    func failures() throws {
        let time = Engine.Time(tt: 8860, deltaTModel: .espenakMeeus)
        for site in [
            Observer(latitude: 91, longitude: 0), Observer(latitude: .nan, longitude: 0),
            Observer(latitude: 0, longitude: .infinity), Observer(latitude: 0, longitude: 0, height: .nan),
        ] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Events.searchLocalSolarEclipse(after: time, from: site)
            }
        }
        let site = Observer(latitude: 0, longitude: 0)
        let lower = try Events.searchLocalSolarEclipse(
            after: Engine.Time(tt: -Engine.acceptedTTDays, deltaTModel: .espenakMeeus), from: site)
        #expect(lower.physicalPeak.tt >= -Engine.acceptedTTDays && lower.physicalPeak.tt <= Engine.acceptedTTDays)
        for tt in [
            Double.nan, Double.infinity, -Engine.acceptedTTDays - 1, Engine.acceptedTTDays + 1, Engine.acceptedTTDays,
        ] {
            #expect(throws: AstronomyError.badTime) {
                try Events.searchLocalSolarEclipse(after: Engine.Time(tt: tt, deltaTModel: .espenakMeeus), from: site)
            }
        }
        #expect(throws: AstronomyError.searchFailure) {
            try Events.localSolarTransition(
                from: time, to: time.adding(days: 0.001), rising: true, observer: site, interior: false)
        }
    }

    @Test("NASA Washington catalog independently identifies consecutive visible events")
    func publishedNext() throws {
        let source = try JSONDecoder().decode(
            References.self,
            from: Data(
                contentsOf: EngineGlobalSolarEventTests.root.appendingPathComponent(
                    "Scripts/eclipse-data/local-references.json"))
        ).sequence
        let site = Observer(latitude: source.latitude, longitude: source.longitude, height: 0)
        let first = try Events.searchLocalSolarEclipse(
            after: Engine.Time(
                ut: try #require(source.events.first?.gmtCalendarDays["peak"]) - 10, deltaTModel: .espenakMeeus),
            from: site)
        let next = try Events.nextLocalSolarEclipse(after: first, from: site)
        var rows: [[String: Any]] = []
        for (event, reference) in zip([first, next], source.events) {
            let day = try #require(reference.gmtCalendarDays["peak"])
            // Calendar-date identity establishes the published sequence. The historical GMT/minute table does not supply a modern model timing uncertainty.
            #expect(floor(event.peak.time.ut + 0.5) == floor(day + 0.5))
            #expect(event.kind.rawValue == reference.localKind && event.isVisible)
            rows.append([
                "date": reference.date, "ut": event.peak.time.ut, "tt": event.peak.time.tt, "kind": event.kind.rawValue,
                "obscuration": event.obscuration, "altitude": event.peak.altitude, "gmtPeak": day,
            ])
        }
        try Self.write(rows, name: "sequence")
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["LOCAL_SOLAR_MEASUREMENT"] != nil))
    func resources() throws {
        func peakBytes() -> Int {
            var usage = rusage()
            #if canImport(Darwin)
            getrusage(RUSAGE_SELF, &usage)
            return Int(usage.ru_maxrss)
            #else
            getrusage(__rusage_who_t(RUSAGE_SELF.rawValue), &usage)
            return Int(usage.ru_maxrss) * 1024
            #endif
        }
        let site = Observer(latitude: 38 + 53 / 60, longitude: -77 - 2 / 60)
        let before = peakBytes()
        let start = Date()
        var event = try Events.searchLocalSolarEclipse(
            after: Engine.Time(tt: 9000, deltaTModel: .espenakMeeus), from: site)
        let cold = Date().timeIntervalSince(start)
        let after = peakBytes()
        let repeated = Date()
        var checksum = event.peak.time.tt
        for _ in 0..<19 {
            event = try Events.nextLocalSolarEclipse(after: event, from: site)
            checksum += event.peak.time.tt
        }
        try Self.write(
            [
                "coldSeconds": cold, "nextSeconds": Date().timeIntervalSince(repeated), "nextCount": 19,
                "peakBeforeBytes": before, "peakAfterColdBytes": after, "peakAfterWorkloadBytes": peakBytes(),
                "checksum": checksum, "host": ProcessInfo.processInfo.operatingSystemVersionString,
            ], name: "resources")
    }
}

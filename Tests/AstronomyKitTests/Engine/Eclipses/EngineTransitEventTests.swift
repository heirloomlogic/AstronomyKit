import Foundation
import Testing

@testable import AstronomyKit

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@Suite("Native planetary transits")
struct EngineTransitEventTests {
    typealias Events = Engine.Events

    static func body(_ name: String) -> CelestialBody { name == "mercury" ? .mercury : .venus }

    @Test("NASA UT contacts and geocentric minimum separation retain their allowances")
    func published() throws {
        var rows: [[String: Any]] = []
        for reference in IndependentReferenceArchive.shared.transits {
            let source = IndependentReferenceDate.engine(reference.peakUTC)
            let event = try Events.searchTransit(of: Self.body(reference.body), after: source.adding(days: -100))
            #expect(
                abs(event.start.ut - IndependentReferenceDate.engine(reference.startUTC).ut) * 86400
                    <= reference.timeToleranceSeconds)
            #expect(abs(event.peak.ut - source.ut) * 86400 <= reference.timeToleranceSeconds)
            #expect(
                abs(event.finish.ut - IndependentReferenceDate.engine(reference.finishUTC).ut) * 86400
                    <= reference.timeToleranceSeconds)
            #expect(
                abs(event.separationArcminutes - reference.separationArcminutes)
                    <= reference.separationToleranceArcminutes)
            #expect(event.start.tt < event.physicalPeak.tt && event.physicalPeak.tt < event.finish.tt)
            let publicEvent = try AstronomyKit.Transit.search(
                body: Self.body(reference.body),
                after: IndependentReferenceDate.universal(reference.peakUTC, deltaTModel: .espenakMeeus).addingDays(
                    -100))
            let oldReference = IndependentReferenceDate.civil(reference.peakUTC)
            rows.append([
                "body": reference.body, "source": reference.peakUTC, "sourceUT": source.ut,
                "startUT": event.start.ut, "startTT": event.start.tt, "peakUT": event.peak.ut, "peakTT": event.peak.tt,
                "finishUT": event.finish.ut, "finishTT": event.finish.tt, "separation": event.separationArcminutes,
                "publicPeakUT": publicEvent.peak.universalTime, "formerUTCReferenceUT": oldReference.universalTime,
                "publicFormerResidualSeconds": (publicEvent.peak.universalTime - oldReference.universalTime) * 86400,
                "publicUTResidualSeconds": (publicEvent.peak.universalTime - source.ut) * 86400,
            ])
        }
        try Self.write(rows, name: "published")
    }

    @Test("Canonical transit identity retains the physical one-second cutoff")
    func identity() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            let first = try Events.searchTransit(of: .mercury, after: Engine.Time(ut: 7200, deltaTModel: model))
            let cutoff = first.physicalPeak.tt + 1 / 86400.0
            for tt in [first.physicalPeak.tt - 0.1, first.physicalPeak.tt, cutoff] {
                let same = try Events.searchTransit(of: .mercury, after: Engine.Time(tt: tt, deltaTModel: model))
                #expect(same.physicalPeak.tt == first.physicalPeak.tt)
                #expect(same.peak.tt >= tt)
                #expect(same.peak.deltaTModel == model)
                #expect(same.start.tt == first.start.tt && same.finish.tt == first.finish.tt)
            }
            let later = try Events.searchTransit(
                of: .mercury, after: Engine.Time(tt: cutoff.nextUp, deltaTModel: model))
            #expect(later.physicalPeak.tt > first.finish.tt)
            #expect(try Events.nextTransit(after: first).physicalPeak.tt == later.physicalPeak.tt)
        }
    }

    @Test("Transit bodies and accepted epochs fail before searching")
    func errors() throws {
        let time = Engine.Time(ut: 0, deltaTModel: .espenakMeeus)
        for body in [CelestialBody.earth, .moon, .sun, .mars, .pluto] {
            #expect(throws: AstronomyError.invalidBody) { try Events.searchTransit(of: body, after: time) }
        }
        for tt in [Double.nan, .infinity, -Engine.acceptedTTDays - 1, Engine.acceptedTTDays + 1] {
            #expect(throws: AstronomyError.badTime) {
                try Events.searchTransit(of: .venus, after: Engine.Time(tt: tt, deltaTModel: .espenakMeeus))
            }
        }
    }

    static func write(_ value: Any, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["TRANSIT_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
            to: url.appendingPathComponent(name + ".json"))
    }

    struct References: Decodable {
        let transitSequences: [String: [TransitReference]]
        let lunarSequence: [LunarReference]
        let danjonContacts: [LunarReference]
        let globalSequence: [GlobalReference]
        struct TransitReference: Decodable {
            let date: String
            let body: String
            let startUT: Double
            let peakUT: Double
            let finishUT: Double
            let separationArcminutes: Double
            let timeToleranceSeconds: Double
            let separationToleranceArcminutes: Double
        }
        struct LunarReference: Decodable {
            let date: String
            let kind: String
            let contactsUT: [String: Double]
            let timeToleranceSeconds: Double
        }
        struct GlobalReference: Decodable {
            let date: String
            let tt: Double
            let kind: String
            let timeToleranceSeconds: Double
        }
    }
    static func references() throws -> References {
        try JSONDecoder().decode(
            References.self,
            from: Data(
                contentsOf: EngineGlobalSolarEventTests.root.appendingPathComponent(
                    "Scripts/eclipse-data/transit-references.json")))
    }

    @Test("Complete NASA catalogs establish consecutive transit, lunar and global events")
    func sequences() throws {
        let refs = try Self.references()
        var transitRows: [[String: Any]] = []
        for body in ["mercury", "venus"] {
            let expected = try #require(refs.transitSequences[body])
            var event = try Events.searchTransit(
                of: Self.body(body),
                after: Engine.Time(ut: try #require(expected.first).peakUT - 100, deltaTModel: .espenakMeeus))
            for (index, row) in expected.enumerated() {
                if index > 0 { event = try Events.nextTransit(after: event) }
                #expect(abs(event.peak.ut - row.peakUT) * 86400 <= row.timeToleranceSeconds)
                #expect(abs(event.start.ut - row.startUT) * 86400 <= row.timeToleranceSeconds)
                #expect(abs(event.finish.ut - row.finishUT) * 86400 <= row.timeToleranceSeconds)
                #expect(abs(event.separationArcminutes - row.separationArcminutes) <= row.separationToleranceArcminutes)
                transitRows.append([
                    "date": row.date, "body": body, "ut": event.peak.ut, "tt": event.peak.tt, "startUT": event.start.ut,
                    "finishUT": event.finish.ut, "separation": event.separationArcminutes,
                ])
            }
        }
        try Self.write(transitRows, name: "transit-sequence")
        var lunar = try Events.searchLunarEclipse(after: Engine.Time(ut: 360, deltaTModel: .espenakMeeus))
        var lunarRows: [[String: Any]] = []
        for (index, row) in refs.lunarSequence.enumerated() {
            if index > 0 { lunar = try Events.nextLunarEclipse(after: lunar) }
            #expect(lunar.kind.rawValue == row.kind)
            #expect(abs(lunar.peak.ut - (try #require(row.contactsUT["peak"]))) * 86400 <= row.timeToleranceSeconds)
            let contacts = try Events.lunarShadowContacts(
                at: lunar.physicalPeak, contact: .penumbral, windowMinutes: 200)
            let matched = refs.danjonContacts[index]
            #expect(
                abs(contacts.ingress.ut - (try #require(matched.contactsUT["penumbralBegin"]))) * 86400
                    <= matched.timeToleranceSeconds)
            #expect(
                abs(contacts.egress.ut - (try #require(matched.contactsUT["penumbralEnd"]))) * 86400
                    <= matched.timeToleranceSeconds)
            // Retain the older-model comparison as measured evidence, including its December failures.
            let oldIngress = (contacts.ingress.ut - (try #require(row.contactsUT["penumbralBegin"]))) * 86400
            let oldEgress = (contacts.egress.ut - (try #require(row.contactsUT["penumbralEnd"]))) * 86400
            #expect((abs(oldIngress) <= row.timeToleranceSeconds) == (index != 2))
            #expect((abs(oldEgress) <= row.timeToleranceSeconds) == (index != 2))
            #expect(contacts.ingress.tt < lunar.physicalPeak.tt && lunar.physicalPeak.tt < contacts.egress.tt)
            lunarRows.append([
                "date": row.date, "kind": lunar.kind.rawValue, "ut": lunar.peak.ut, "tt": lunar.peak.tt,
                "ingressUT": contacts.ingress.ut, "egressUT": contacts.egress.ut,
                "semiDurationMinutes": lunar.penumbralDurationMinutes,
            ])
        }
        try Self.write(lunarRows, name: "lunar-sequence")
        var global = try Events.searchGlobalSolarEclipse(
            after: Engine.Time(tt: try #require(refs.globalSequence.first).tt - 10, deltaTModel: .espenakMeeus))
        var globalRows: [[String: Any]] = []
        for (index, row) in refs.globalSequence.enumerated() {
            if index > 0 { global = try Events.nextGlobalSolarEclipse(after: global) }
            #expect(global.kind.rawValue == row.kind)
            #expect(abs(global.peak.tt - row.tt) * 86400 <= row.timeToleranceSeconds)
            globalRows.append([
                "date": row.date, "kind": global.kind.rawValue, "ut": global.peak.ut, "tt": global.peak.tt,
            ])
        }
        try Self.write(globalRows, name: "global-sequence")
    }

    @Test("Transit angular minimum and exterior tangencies have the required signs")
    func geometry() throws {
        for body in [CelestialBody.mercury, .venus] {
            let event = try Events.searchTransit(of: body, after: Engine.Time(ut: 0, deltaTModel: .espenakMeeus))
            let minimum = try Events.transitGeometry(of: body, at: event.physicalPeak).separationRadians
            for step in [-60.0, 60.0] {
                #expect(
                    try Events.transitGeometry(of: body, at: event.physicalPeak.adding(days: step / 86400))
                        .separationRadians > minimum)
            }
            for (contact, sign) in [(event.start, 1.0), (event.finish, -1.0)] {
                #expect(
                    try sign * Events.transitGeometry(of: body, at: contact.adding(days: -2 / 86400.0)).exteriorMargin
                        < 0)
                #expect(
                    try sign * Events.transitGeometry(of: body, at: contact.adding(days: 2 / 86400.0)).exteriorMargin
                        > 0)
            }
            #expect(throws: AstronomyError.searchFailure) {
                try Events.transitContact(
                    of: body, from: event.start.adding(days: -1), to: event.start.adding(days: -0.5), ingress: true)
            }
            let clamp = try #require(
                Events.resolvedTransit(
                    event, atOrAfter: Engine.Time(tt: event.physicalPeak.tt + 1 / 86400.0, deltaTModel: .espenakMeeus)))
            #expect(
                Events.resolvedTransit(
                    clamp,
                    atOrAfter: Engine.Time(tt: (event.physicalPeak.tt + 1 / 86400.0).nextUp, deltaTModel: .espenakMeeus)
                ) == nil)
        }
    }

    @Test("Source UT remains distinct from UTC encoding and model TT")
    func sourceEpochs() {
        for reference in IndependentReferenceArchive.shared.transits {
            let time = IndependentReferenceDate.universal(reference.peakUTC, deltaTModel: .espenakMeeus)
            let native = IndependentReferenceDate.engine(reference.peakUTC)
            #expect(time.universalTime == native.ut)
            #expect(Engine.Time(tt: native.tt, deltaTModel: .espenakMeeus).ut == native.ut)
            #expect(IndependentReferenceDate.civil(reference.peakUTC).universalTime != native.ut)
        }
    }

    @Test("Canonical conjunctions are independent of nearby discovery estimates")
    func conjunctions() throws {
        for body in [CelestialBody.mercury, .venus] {
            for tt in [0.0, 7200.0, 45000.0] {
                let found = try Events.searchRelativeLongitude(
                    of: body, targetDegrees: 0, after: Engine.Time(tt: tt, deltaTModel: .espenakMeeus))
                let first = try Events.canonicalTransitConjunction(of: body, near: found)
                for perturbation in [-0.000001, 0.000001] {
                    let other = try Events.canonicalTransitConjunction(
                        of: body, near: Engine.Time(tt: found.tt + perturbation, deltaTModel: .espenakMeeus))
                    #expect(first.tt == other.tt)
                }
            }
        }
    }

    @Test("Finite search endpoints and lunar contact errors remain explicit")
    func endpoints() throws {
        for body in [CelestialBody.mercury, .venus] {
            let lower = Engine.Time(tt: -Engine.acceptedTTDays, deltaTModel: .espenakMeeus)
            let first = try Events.searchTransit(of: body, after: lower)
            #expect(first.peak.tt >= lower.tt && first.finish.tt < Engine.acceptedTTDays)
            #expect(throws: AstronomyError.badTime) {
                try Events.searchTransit(
                    of: body, after: Engine.Time(tt: Engine.acceptedTTDays, deltaTModel: .espenakMeeus))
            }
        }
        for width in [0.0, -1.0, .infinity, .nan] {
            #expect(throws: AstronomyError.searchFailure) {
                try Events.lunarShadowContacts(
                    at: Engine.Time(tt: 0, deltaTModel: .espenakMeeus), contact: .penumbral, windowMinutes: width)
            }
        }
        let tangent = Events.TransitGeometry(separationRadians: 0.6, sunRadiusRadians: 0.5, planetRadiusRadians: 0.1)
        #expect(tangent.exteriorMargin == 0)
        #expect(
            Events.TransitGeometry(separationRadians: 0.6.nextUp, sunRadiusRadians: 0.5, planetRadiusRadians: 0.1)
                .exteriorMargin < 0)
        #expect(
            Events.TransitGeometry(separationRadians: 0.6.nextDown, sunRadiusRadians: 0.5, planetRadiusRadians: 0.1)
                .exteriorMargin > 0)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["TRANSIT_MEASUREMENT"] != nil))
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
        let before = peakBytes()
        let start = Date()
        var event = try Events.searchTransit(of: .mercury, after: Engine.Time(tt: 0, deltaTModel: .espenakMeeus))
        let cold = Date().timeIntervalSince(start)
        let after = peakBytes()
        let repeated = Date()
        var checksum = event.physicalPeak.tt
        for _ in 0..<19 {
            event = try Events.nextTransit(after: event)
            checksum += event.physicalPeak.tt
        }
        try Self.write(
            [
                "coldSeconds": cold, "nextSeconds": Date().timeIntervalSince(repeated), "nextCount": 19,
                "peakBeforeBytes": before, "peakAfterColdBytes": after, "peakAfterWorkloadBytes": peakBytes(),
                "checksum": checksum, "host": ProcessInfo.processInfo.operatingSystemVersionString,
            ], name: "resources")
    }
}

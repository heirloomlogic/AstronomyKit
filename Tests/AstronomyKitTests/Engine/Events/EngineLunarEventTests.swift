import Testing

@testable import AstronomyKit

@Suite("Engine.Events lunar searches")
struct EngineLunarEventTests {
    typealias Events = Engine.Events

    static func universalTime(_ utc: String, model: DeltaTModel = .espenakMeeus) -> Engine.Time {
        Engine.Time(ut: IndependentReferenceDate.universal(utc, deltaTModel: model).universalTime, deltaTModel: model)
    }

    static func eventTime(_ utc: String) -> Engine.Time {
        Engine.Time(tt: IndependentReferenceDate.civil(utc).terrestrialTime, deltaTModel: .espenakMeeus)
    }

    @Test("Published node and apsis UTC labels retain civil-time semantics")
    func publishedEventTimeSemantics() {
        for utc in ["2100-01-01T21:13Z", "2100-01-17T10:48Z"] {
            #expect(Self.eventTime(utc).tt == IndependentReferenceDate.civil(utc).terrestrialTime)
        }
    }

    @Test("Published quarters retain their 90-second allowances and ordering")
    func publishedQuarters() throws {
        for reference in IndependentReferenceArchive.shared.lunarPhases {
            let expected = Self.universalTime(reference.sourceTime)
            let actual = try Events.searchMoonQuarter(after: expected.adding(days: -2))
            let phase: Events.LunarPhase =
                switch reference.phase {
                case "new": .new
                case "firstQuarter": .firstQuarter
                case "full": .full
                case "lastQuarter": .lastQuarter
                default: throw AstronomyError.internalError
                }
            #expect(actual.phase == phase)
            #expect(abs(actual.time.tt - expected.tt) * Engine.secondsPerDay <= reference.toleranceSeconds)
        }
    }

    @Test("Published true-ecliptic nodes retain direction and their time allowances")
    func publishedNodes() throws {
        for reference in IndependentReferenceArchive.shared.lunarNodes {
            let expected = Self.eventTime(reference.utc)
            let actual = try Events.searchLunarNode(after: expected.adding(days: -5))
            #expect(actual.kind == (reference.kind == "ascending" ? .ascending : .descending))
            #expect(abs(actual.time.tt - expected.tt) * Engine.secondsPerDay <= reference.timeToleranceSeconds)
            let latitudeRate = try Engine.Moon.eclipticState(at: actual.time).latitudeRate
            #expect((latitudeRate > 0) == (actual.kind == .ascending))
        }
    }

    @Test("Published lunar apsides retain kind, time, and distance allowances")
    func publishedApsides() throws {
        for reference in IndependentReferenceArchive.shared.lunarApsides {
            let expected = Self.eventTime(reference.utc)
            let actual = try Events.searchLunarApsis(after: expected.adding(days: -5))
            #expect(actual.kind == (reference.kind == "pericenter" ? .pericenter : .apocenter))
            #expect(abs(actual.time.tt - expected.tt) * Engine.secondsPerDay <= reference.timeToleranceSeconds)
            #expect(
                abs(actual.distanceKilometers - (try #require(reference.distanceKM)))
                    <= (try #require(reference.distanceToleranceKM)))
        }
    }

    @Test("Phase windows preserve direction, endpoints, nil, and the captured model")
    func phaseWindows() throws {
        let expected = Self.universalTime("2025-01-13T22:27:00.000Z", model: .jplHorizons)
        let forward = try #require(
            try Events.searchMoonPhase(180, after: expected.adding(days: -2), limitDays: 4))
        let backward = try #require(
            try Events.searchMoonPhase(180, after: expected.adding(days: 2), limitDays: -4))
        #expect(abs(forward.tt - backward.tt) * Engine.secondsPerDay < 0.2)
        #expect(forward.deltaTModel == .jplHorizons && backward.deltaTModel == .jplHorizons)
        #expect(try Events.searchMoonPhase(180, after: expected.adding(days: -2), limitDays: 1) == nil)

        let endpoint = Engine.Time(tt: Engine.acceptedTTDays, deltaTModel: .jplHorizons)
        let target = try Events.moonPhaseAngle(at: endpoint)
        let same = try #require(try Events.searchMoonPhase(target, after: endpoint, limitDays: 0))
        #expect(same.tt == endpoint.tt && same.deltaTModel == .jplHorizons)
    }

    @Test("Quarter, node, and apsis advancement preserves alternation and progress")
    func advancement() throws {
        let start = Self.universalTime("2025-01-01T00:00:00.000Z", model: .jplHorizons)
        let quarter = try Events.searchMoonQuarter(after: start)
        let nextQuarter = try Events.nextMoonQuarter(after: quarter)
        #expect(nextQuarter.phase.rawValue == (quarter.phase.rawValue + 1) % 4)
        #expect(nextQuarter.time.tt > quarter.time.tt && nextQuarter.time.deltaTModel == .jplHorizons)

        let node = try Events.searchLunarNode(after: start)
        let nextNode = try Events.nextLunarNode(after: node)
        #expect(nextNode.kind != node.kind)
        #expect(nextNode.time.tt > node.time.tt && nextNode.time.deltaTModel == .jplHorizons)

        let apsis = try Events.searchLunarApsis(after: start)
        let nextApsis = try Events.nextLunarApsis(after: apsis)
        #expect(nextApsis.kind != apsis.kind)
        #expect(nextApsis.time.tt > apsis.time.tt && nextApsis.time.deltaTModel == .jplHorizons)
    }

    @Test("Lunar searches reject nonfinite inputs and evaluations beyond the accepted range")
    func invalidInputs() {
        let start = Self.universalTime("2025-01-01T00:00:00.000Z")
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Events.searchMoonPhase(value, after: start, limitDays: 30)
            }
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try Events.searchMoonPhase(0, after: start, limitDays: value)
            }
        }
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchMoonQuarter(after: .invalid) }
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchLunarNode(after: .invalid) }
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchLunarApsis(after: .invalid) }

        let nearEnd = Engine.Time(tt: Engine.acceptedTTDays - 1, deltaTModel: .espenakMeeus)
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchLunarNode(after: nearEnd) }
        #expect(throws: AstronomyError.badTime) { _ = try Events.searchLunarApsis(after: nearEnd) }
    }
}

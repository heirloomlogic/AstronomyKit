import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native observer events")
struct EngineObserverEventsTests {
    private let observer = Observer(latitude: 35, longitude: -80, height: 0)
    private let start = Engine.Time(ut: 8_000, deltaTModel: .espenakMeeus)

    @Test("Hour-angle search returns the requested native observable")
    func hourAngle() throws {
        let event = try Engine.Events.searchHourAngle(
            of: .sun, hourAngle: 0, after: start, from: observer, direction: 1)
        #expect(event.time.ut >= start.ut)
        #expect(event.time.ut < start.ut + 1.1)
        let angle = try Engine.Events.hourAngle(of: .sun, at: event.time, from: observer)
        #expect(min(angle, 24 - angle) * 3_600 < 0.1)
        #expect(event.time.deltaTModel == start.deltaTModel)
    }

    @Test("Rise and set bracket an upper-limb horizon crossing")
    func riseSet() throws {
        for direction in [RiseSetDirection.rise, .set] {
            let result = try #require(
                try Engine.Events.searchRiseSet(
                    of: .sun, direction: direction, after: start, from: observer, limitDays: 2))
            let before = try Engine.Events.altitudeResidual(
                of: .sun, at: result.adding(days: -1 / 86_400), from: observer,
                bodyRadiusAU: 696_000 / Engine.kilometersPerAU, targetDegrees: -34 / 60)
            let after = try Engine.Events.altitudeResidual(
                of: .sun, at: result.adding(days: 1 / 86_400), from: observer,
                bodyRadiusAU: 696_000 / Engine.kilometersPerAU, targetDegrees: -34 / 60)
            #expect(before * Double(direction.rawValue) < 0)
            #expect(after * Double(direction.rawValue) > 0)
        }
    }

    @Test("Frozen fuzz inputs fail before iteration")
    func fuzzGuards() throws {
        let star = Engine.Star(rightAscension: 0, declination: 89, distance: 1_000)
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Events.searchRiseSet(
                of: .star(star), direction: .rise,
                after: Engine.Time(ut: 9_497.5, deltaTModel: .espenakMeeus),
                from: Observer(latitude: 80, longitude: 0), limitDays: .infinity)
        }
        #expect(throws: AstronomyError.badTime) {
            try Engine.Events.searchRiseSet(
                of: .moon, direction: .rise,
                after: Engine.Time(ut: 4_503_599_627_370_493, deltaTModel: .espenakMeeus),
                from: Observer(latitude: 0, longitude: 0), limitDays: 10)
        }
    }

    @Test("Valid short windows at the accepted boundary do not probe outside it")
    func boundedDomain() throws {
        let time = Engine.Time(tt: 1_461_000 - 0.001, deltaTModel: .espenakMeeus)
        let result = try Engine.Events.searchAltitude(
            of: .sun, direction: .rise, after: time,
            from: Observer(latitude: 90, longitude: 0), limitDays: 0.0005, altitudeDegrees: 90)
        #expect(result == nil)
        #expect(throws: AstronomyError.badTime) {
            try CelestialBody.sun.searchAltitude(
                90, direction: .rise,
                after: AstroTime(tt: time.tt, deltaTModel: .espenakMeeus),
                from: Observer(latitude: 90, longitude: 0), limitDays: 0.0005)
        }
    }

    @Test("Directions, clipped windows, and captured models")
    func directionalWindows() throws {
        for model in [DeltaTModel.espenakMeeus, .jplHorizons] {
            let time = Engine.Time(ut: 8_000, deltaTModel: model)
            let forward = try Engine.Events.searchHourAngle(
                of: .sun, hourAngle: 12, after: time, from: observer, direction: 1)
            let backward = try Engine.Events.searchHourAngle(
                of: .sun, hourAngle: 12, after: time, from: observer, direction: -1)
            #expect(forward.time.ut >= time.ut)
            #expect(backward.time.ut <= time.ut)
            #expect(forward.time.deltaTModel == model)
            #expect(backward.time.deltaTModel == model)
            let repeated = try Engine.Events.searchHourAngle(
                of: .sun, hourAngle: 12, after: forward.time, from: observer, direction: 1)
            #expect(repeated.time.ut == forward.time.ut)
            let rise = try #require(
                try Engine.Events.searchAltitude(
                    of: .sun, direction: .rise, after: time, from: observer, limitDays: 2, altitudeDegrees: -6))
            let reverse = try #require(
                try Engine.Events.searchAltitude(
                    of: .sun, direction: .rise, after: rise.adding(days: 0.1), from: observer, limitDays: -0.2,
                    altitudeDegrees: -6))
            #expect(abs(rise.tt - reverse.tt) * 86_400 < 0.2)
            let absent = try Engine.Events.searchAltitude(
                of: .sun, direction: .rise, after: rise.adding(days: 0.1), from: observer, limitDays: -0.05,
                altitudeDegrees: -6)
            #expect(absent == nil)
        }
    }

    @Test("Nonfinite, invalid observers and unsupported bodies remain errors")
    func invalidInputs() {
        for limit in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Engine.Events.searchAltitude(
                    of: .sun, direction: .rise, after: start, from: observer, limitDays: limit, altitudeDegrees: 0)
            }
        }
        for altitude in [Double.nan, .infinity, -90.01, 90.01] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Engine.Events.searchAltitude(
                    of: .sun, direction: .rise, after: start, from: observer, limitDays: 1, altitudeDegrees: altitude)
            }
        }
        for height in [Double.nan, .infinity, -1] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Engine.Events.searchRiseSet(
                    of: .sun, direction: .rise, after: start, from: observer, limitDays: 1, heightAboveGround: height)
            }
        }
        #expect(throws: AstronomyError.earthNotAllowed) {
            try Engine.Events.searchAltitude(
                of: .earth, direction: .rise, after: start, from: observer, limitDays: 1, altitudeDegrees: 0)
        }
        #expect(throws: AstronomyError.invalidBody) {
            try Engine.Events.searchAltitude(
                of: .io, direction: .rise, after: start, from: observer, limitDays: 1, altitudeDegrees: 0)
        }
        #expect(throws: AstronomyError.badTime) {
            try Engine.Events.searchAltitude(
                of: .sun, direction: .rise, after: .invalid, from: observer, limitDays: 1, altitudeDegrees: 0)
        }
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Events.hourAngle(of: .sun, at: start, from: Observer(latitude: 91, longitude: 0))
        }
        for target in [Double.nan, .infinity, -1, 24] {
            #expect(throws: AstronomyError.invalidParameter) {
                try Engine.Events.searchHourAngle(
                    of: .sun, hourAngle: target, after: start, from: observer, direction: 1)
            }
        }
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Events.searchHourAngle(of: .sun, hourAngle: 0, after: start, from: observer, direction: 0)
        }
    }

    @Test("Long finite circumpolar windows finish with no event")
    func longWindow() throws {
        let star = Engine.Star(rightAscension: 0, declination: 89, distance: 1_000)
        for limit in [-1_000.0, 0, 1_000] {
            let result = try Engine.Events.searchRiseSet(
                of: .star(star), direction: .rise, after: start,
                from: Observer(latitude: 80, longitude: 0), limitDays: limit)
            #expect(result == nil)
        }
    }

    @Test("Subdivision distinguishes a tangent from a short real crossing")
    func tangent() throws {
        let lower = Engine.Time(ut: 0, deltaTModel: .espenakMeeus)
        let upper = lower.adding(days: 1)
        for depth in [0.0, 0.0001] {
            func value(_ time: Engine.Time) -> Double { (time.ut - 0.5) * (time.ut - 0.5) - depth }
            let bracket = try Engine.Events.altitudeAscent(
                lower: lower, upper: upper,
                lowValue: value(lower), highValue: value(upper), maximumSlope: 1, evaluate: value)
            if depth == 0 {
                #expect(bracket == nil)
            } else {
                let found = try #require(bracket)
                let root = try #require(
                    try Engine.Search.ascendingRoot(from: found.0, to: found.1, toleranceSeconds: 0.1, value))
                #expect(abs(root.ut - 0.51) * 86_400 < 0.1)
            }
        }
    }

    @Test("Observer height and atmospheric horizon composition")
    func horizonHeight() throws {
        let ground = Observer(latitude: 35, longitude: -80, height: 500)
        let elevated = Observer(latitude: 35, longitude: -80, height: 600)
        let seaLevel = try #require(
            try Engine.Events.searchRiseSet(of: .sun, direction: .rise, after: start, from: observer, limitDays: 1))
        let highGround = try #require(
            try Engine.Events.searchRiseSet(of: .sun, direction: .rise, after: start, from: ground, limitDays: 1))
        let tower = try #require(
            try Engine.Events.searchRiseSet(
                of: .sun, direction: .rise, after: start, from: elevated, limitDays: 1, heightAboveGround: 100))
        #expect(highGround.ut > seaLevel.ut)
        #expect(tower.ut < highGround.ut)
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Events.searchRiseSet(
                of: .sun, direction: .rise, after: start, from: observer, limitDays: 1, heightAboveGround: 501)
        }
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Events.searchRiseSet(
                of: .sun, direction: .rise, after: start, from: Observer(latitude: 35, longitude: -80, height: 100_001),
                limitDays: 1)
        }
    }

    @Test("All 5,909 archived USNO events", arguments: IndependentReferenceArchive.shared.riseSetStreams)
    func usno(stream: IndependentReferenceArchive.RiseSetStream) throws {
        let year = try #require(Int(stream.events[0].utc.prefix(4)))
        let site = Observer(latitude: stream.latitudeDegrees, longitude: stream.longitudeDegrees)
        let body = try #require(CelestialBody.allCases.first { $0.name.lowercased() == stream.body })
        let time = Engine.Time(
            ut: Engine.Time.days(year: year, month: 1, day: 1, hour: 0, minute: 0, second: 0),
            deltaTModel: .espenakMeeus)
        var riseStart = time
        var setStart = time
        var actual: [(Engine.Time, RiseSetDirection)] = []
        while actual.count < stream.events.count {
            let rise = try #require(
                try Engine.Events.searchRiseSet(
                    of: body, direction: .rise, after: riseStart, from: site, limitDays: 366))
            let set = try #require(
                try Engine.Events.searchRiseSet(of: body, direction: .set, after: setStart, from: site, limitDays: 366))
            riseStart = rise.adding(days: 1e-5)
            setStart = set.adding(days: 1e-5)
            actual += rise.tt < set.tt ? [(rise, .rise), (set, .set)] : [(set, .set), (rise, .rise)]
        }
        actual = Array(actual.prefix(stream.events.count))
        #expect(actual.count == stream.events.count)
        var maximum = 0.0
        var records: [[String: Any]] = []
        for (index, pair) in actual.enumerated() {
            let reference = stream.events[index]
            let expected = IndependentReferenceDate.universal(reference.utc, deltaTModel: .espenakMeeus)
            let residual = abs(pair.0.tt - expected.terrestrialTime) * Engine.secondsPerDay
            maximum = max(maximum, residual)
            records.append([
                "sourceLine": reference.sourceLine, "nativeTT": pair.0.tt, "nativeUT": pair.0.ut,
                "referenceTT": expected.terrestrialTime, "referenceUT": expected.universalTime,
                "direction": pair.1 == .rise ? "rise" : "set",
                "residualSeconds": residual,
            ])
            #expect((pair.1 == .rise ? "rise" : "set") == reference.direction)
            #expect(
                residual <= reference.timeToleranceSeconds, "USNO line \(reference.sourceLine): \(residual) seconds")
            if index > 0 { #expect(pair.0.tt > actual[index - 1].0.tt) }
        }
        try EngineObserverSourceTests.write(records, name: "usno-\(stream.events[0].sourceLine)")
        print("USNO_NATIVE \(stream.testDescription) maxSeconds=\(maximum)")
    }
}

//
//  EngineRotationAxisTests.swift
//  AstronomyKit
//
//  Rotation axes against the IAU WGCCRE elements as NAIF's PCK publishes
//  them, Earth's pole against the IAU 2006 precession, and the guards.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.RotationAxis")
struct EngineRotationAxisTests {
    typealias Axes = Engine.RotationAxis

    /// A time at `tt` with its UT from the Espenak-Meeus Delta T, so a body
    /// that rotated with UT instead of TT would fail.
    static func time(tt: Double) -> Engine.Time { Engine.Time(tt: tt, deltaTModel: .espenakMeeus) }

    static func tdb(tt: Double) -> Double { tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay }

    static func vector<F>(_ v: Engine.Vector<F>) -> SIMD3<Double> { SIMD3(v.x, v.y, v.z) }

    /// The angle in arcseconds between two directions.
    static func arcseconds(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let cross = SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        return atan2(EngineGravityTests.length(cross), (a * b).sum()) * Engine.degreesPerRadian * 3600
    }

    // MARK: - The published elements

    /// A failure to read the PCK.
    struct PCKError: Error, CustomStringConvertible {
        let description: String
    }

    /// The `\begindata` assignments of NAIF's `pck00011.tpc`, copied unchanged
    /// into `Scripts/reference-data/sources/naif` (URL and SHA-256 in
    /// `build-fixtures.py`, which checks the hash). NAIF transcribes the IAU
    /// WGCCRE 2015 report into it, and the 2009 report for Earth and the
    /// Moon. A file that does not parse fails the tests that read it.
    static let pck = Result { () throws -> [String: [Double]] in
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Bodies
            .deletingLastPathComponent()  // Engine
            .deletingLastPathComponent()  // AstronomyKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/reference-data/sources/naif/pck00011.tpc")
        var data = ""
        var inData = false
        let text = try String(contentsOf: url, encoding: .utf8)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "\\begindata" {
                inData = true
            } else if trimmed == "\\begintext" {
                inData = false
            } else if inData {
                data += line + "\n"
            }
        }
        var variables: [String: [Double]] = [:]
        var rest = Substring(data)
        while let equals = rest.firstIndex(of: "=") {
            let name = rest[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
            var value = rest[rest.index(after: equals)...].drop { $0 == " " }
            let text: Substring
            if value.first == "(" {
                guard let close = value.firstIndex(of: ")") else { throw PCKError(description: "\(name) has no )") }
                text = value[value.index(after: value.startIndex)..<close]
                value = value[value.index(after: close)...]
            } else {
                let end = value.firstIndex(of: "\n") ?? value.endIndex
                text = value[..<end]
                value = value[end...]
            }
            variables[name] = try text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { field in
                guard let number = Double(field.replacingOccurrences(of: "D", with: "e")) else {
                    throw PCKError(description: "\(name): \(field) is not a number")
                }
                return number
            }
            rest = value
        }
        return variables
    }

    /// The NAIF ID of each body the reports cover.
    static let naifIDs: [CelestialBody: Int] = [
        .sun: 10, .mercury: 199, .venus: 299, .earth: 399, .moon: 301, .mars: 499, .jupiter: 599, .saturn: 699,
        .uranus: 799, .neptune: 899, .pluto: 999,
    ]

    /// α0 and δ0 in degrees and W in degrees from the PCK's polynomials and
    /// nutation-precession terms at `tdb` days of TDB from J2000, as NAIF's
    /// PCK required reading defines them: α0 = a + bT + cT² + Σ aᵢ sin θᵢ,
    /// δ0 = … + Σ dᵢ cos θᵢ, W = … (in d) + Σ wᵢ sin θᵢ, with each angle θᵢ a
    /// polynomial in T of the system's `MAX_PHASE_DEGREE` (1 by default).
    static func published(_ id: Int, tdb d: Double) throws -> (ra: Double, dec: Double, spin: Double) {
        let pck = try Self.pck.get()
        func variable(_ name: String) throws -> [Double] {
            guard let values = pck[name] else { throw PCKError(description: "no \(name)") }
            return values
        }
        let t = d / 36_525
        func polynomial(_ name: String) throws -> [Double] {
            let values = try variable(name)
            guard values.count == 3 else { throw PCKError(description: "\(name) has \(values.count) values, not 3") }
            return values
        }
        let ra = try polynomial("BODY\(id)_POLE_RA")
        let dec = try polynomial("BODY\(id)_POLE_DEC")
        let pm = try polynomial("BODY\(id)_PM")
        var result = (
            ra: ra[0] + ra[1] * t + ra[2] * t * t, dec: dec[0] + dec[1] * t + dec[2] * t * t,
            spin: pm[0] + pm[1] * d + pm[2] * d * d
        )
        let terms = ["RA", "DEC", "PM"].map { pck["BODY\(id)_NUT_PREC_\($0)"] ?? [] }
        guard terms.contains(where: { !$0.isEmpty }) else { return result }
        // A satellite's angles are its system's: 301 reads BODY3_.
        let system = id / 100
        let angles = try variable("BODY\(system)_NUT_PREC_ANGLES")
        let degree = Int(pck["BODY\(system)_MAX_PHASE_DEGREE"]?.first ?? 1)
        guard angles.count % (degree + 1) == 0 else {
            throw PCKError(description: "BODY\(system)_NUT_PREC_ANGLES is not in groups of \(degree + 1)")
        }
        // Spelled out step by step: Linux's type checker gives up on the
        // nested map/reduce form.
        func angle(at start: Int) -> Double {
            var degrees = 0.0
            for power in 0...degree {
                let coefficient: Double = angles[start + power]
                degrees += coefficient * pow(t, Double(power))
            }
            return degrees * Engine.radiansPerDegree
        }
        let theta: [Double] = stride(from: 0, to: angles.count, by: degree + 1).map(angle(at:))
        guard terms.allSatisfy({ $0.count <= theta.count }) else {
            throw PCKError(description: "BODY\(id) has more terms than its system has angles")
        }
        for (i, a) in terms[0].enumerated() { result.ra += a * sin(theta[i]) }
        for (i, a) in terms[1].enumerated() { result.dec += a * cos(theta[i]) }
        for (i, a) in terms[2].enumerated() { result.spin += a * sin(theta[i]) }
        return result
    }

    /// The allowance for evaluating the same expressions in another order:
    /// up to 27 terms each rounded once, so 1e-14 (45 roundings) of the
    /// magnitude, plus a turn's worth for angles near zero.
    static func allowance(_ value: Double) -> Double { 1e-14 * (abs(value) + 360) }

    /// 81 times a century apart across the accepted range, both ends
    /// included, and 61 times 13.37 days apart from 2025-12-31 12:00 TT into 2028,
    /// which land at every time of day.
    static let times: [Double] = {
        let centuries = Array(stride(from: -Engine.acceptedTTDays, through: Engine.acceptedTTDays, by: 36_525))
        return centuries + (0...60).map { 9_496.0 + 13.37 * Double($0) }
    }()

    @Test("The sample times reach both ends of the accepted range")
    func timesReachTheEnds() {
        #expect(Self.times.first == -Engine.acceptedTTDays)
        #expect(Self.times.contains(Engine.acceptedTTDays))
        #expect(Self.times.count == 81 + 61)
    }

    /// The bodies whose elements are the reports'; Earth keeps the C
    /// engine's model and has tests of its own.
    static let reportBodies = Axes.bodies.filter { $0 != .earth }

    @Test("Every body but Earth matches the WGCCRE elements of pck00011.tpc", arguments: reportBodies)
    func publishedElements(body: CelestialBody) throws {
        let id = try #require(Self.naifIDs[body])
        for tt in Self.times {
            let axis = try Axes.axis(of: body, at: Self.time(tt: tt))
            let expected = try Self.published(id, tdb: tt)
            // The C engine reduces no report body's right ascension; over the
            // accepted range none leaves 0 to 24 hours.
            #expect((0..<24).contains(axis.rightAscension), "tt \(tt)")
            #expect(abs(axis.rightAscension * 15 - expected.ra) <= Self.allowance(expected.ra), "tt \(tt)")
            #expect(abs(axis.declination - expected.dec) <= Self.allowance(expected.dec), "tt \(tt)")
            #expect(abs(axis.spin - expected.spin) <= Self.allowance(expected.spin), "tt \(tt)")
            let north = Engine.Vector<Engine.EQJ>(
                Engine.Spherical(latitude: expected.dec, longitude: expected.ra, distance: 1), time: .invalid)
            let allowed = 3600 * (Self.allowance(expected.ra) + Self.allowance(expected.dec))
            #expect(Self.arcseconds(Self.vector(axis.north), Self.vector(north)) <= allowed, "tt \(tt)")
        }
    }

    /// The engine, like the C engine, takes TT for the reports' TDB. At the
    /// sample time where TDB − TT is largest, over 1 ms, Jupiter's W moves by
    /// over 1e-5°; the elements evaluated at TDB, or another body's, fail.
    @Test("The check fails for the elements at TDB, or for the wrong body")
    func negativeControls() throws {
        let offsets = Self.times.map { (tt: $0, seconds: abs(Engine.TDB.offsetSeconds(tt: $0))) }
        let largest = try #require(offsets.max { $0.seconds < $1.seconds })
        let late = largest.tt
        #expect(largest.seconds > 1e-3)
        let axis = try Axes.axis(of: .jupiter, at: Self.time(tt: late))
        let atTDB = try Self.published(599, tdb: Self.tdb(tt: late))
        #expect(abs(axis.spin - atTDB.spin) > Self.allowance(atTDB.spin))
        let saturn = try Self.published(699, tdb: late)
        #expect(abs(axis.declination - saturn.dec) > Self.allowance(saturn.dec))
    }

    /// The engine takes TT for the reports' TDB. Over the accepted range
    /// `Engine.TDB.offsetSeconds` reaches 1.840 ms at TT −1,457,107.53 days,
    /// the largest a 2-day scan of the whole range, refined to 0.001 day,
    /// found. Every 100th day stays under 1.85 ms, so W moves by under
    /// 870.536° per day × 1.85 ms, 1.9e-5°, for Jupiter, the fastest.
    @Test("TDB − TT stays under 1.85 ms over the accepted range")
    func tdbOffsetBound() {
        #expect(abs(abs(Engine.TDB.offsetSeconds(tt: -1_457_107.53)) - 1.840e-3) < 5e-7)
        let days = Array(stride(from: -Engine.acceptedTTDays, through: Engine.acceptedTTDays, by: 100))
        #expect(days.first == -Engine.acceptedTTDays && days.last == Engine.acceptedTTDays)
        #expect(days.allSatisfy { abs(Engine.TDB.offsetSeconds(tt: $0)) < 1.85e-3 })
        #expect(870.536 * 1.85e-3 / Engine.secondsPerDay < 1.9e-5)
    }

    // MARK: - The prime meridian

    /// The prime meridian, the body-fixed x axis, that a pole (α0, δ0) and W
    /// place, as NAIF's PCK required reading builds the body-fixed frame:
    /// turn by W about the pole, tilt the pole down from z by 90° − δ0, and
    /// turn the node to right ascension 90° + α0.
    static func primeMeridian(ra: Double, dec: Double, spin: Double) -> SIMD3<Double> {
        let frame = Engine.Rotation<Engine.EQJ, Engine.EQJ>.identity
            .turned(axis: 2, degrees: spin)
            .turned(axis: 0, degrees: 90 - dec)
            .turned(axis: 2, degrees: 90 + ra)
        return frame.apply(to: SIMD3(1.0, 0, 0))
    }

    @Test(
        "The returned pole and W place the prime meridian where the published elements do",
        arguments: reportBodies)
    func primeMeridians(body: CelestialBody) throws {
        let id = try #require(Self.naifIDs[body])
        for tt in Self.times {
            let axis = try Axes.axis(of: body, at: Self.time(tt: tt))
            let expected = try Self.published(id, tdb: tt)
            let returned = Self.primeMeridian(ra: axis.rightAscension * 15, dec: axis.declination, spin: axis.spin)
            let published = Self.primeMeridian(ra: expected.ra, dec: expected.dec, spin: expected.spin)
            let allowed =
                3600 * (Self.allowance(expected.ra) + Self.allowance(expected.dec) + Self.allowance(expected.spin))
            #expect(Self.arcseconds(returned, published) <= allowed, "tt \(tt)")
            #expect(abs((returned * Self.vector(axis.north)).sum()) < 1e-15, "tt \(tt)")
        }
    }

    // MARK: - Earth

    /// Earth's pole against N·P built from SOFA's precession and nutation
    /// angles (`EngineFrameRotationTests.equatorOfDate`) at eight epochs from
    /// 1600 to 2500, with UT1 and TT apart. The pole of date on J2000 axes is
    /// the third row of N·P. The engine's matrix matches that one within
    /// 2e-15 in each element, so the pole is within √3 · 2e-15 radians.
    @Test("Earth's pole is the true pole of date from the IAU 2006/2000B orientation")
    func earthPole() throws {
        let times = PublishedOrientation.references.map(\.tt)
        #expect(times.contains { $0 < 0 } && times.contains { $0 > 0 })
        for reference in PublishedOrientation.references {
            let time = EngineFrameRotationTests.time(reference)
            let axis = try Axes.axis(of: .earth, at: time)
            let row = EngineFrameRotationTests.equatorOfDate(reference)[2]
            let difference = Self.vector(axis.north) - SIMD3(row[0], row[1], row[2])
            #expect(EngineGravityTests.length(difference) <= 3.0.squareRoot() * 2e-15, "\(reference.year)")
            let equatorial = try Engine.Equatorial(axis.north)
            #expect(axis.rightAscension == equatorial.rightAscension)
            #expect(axis.declination == equatorial.declination)
        }
    }

    /// Like the C engine, Earth's right ascension runs from 0 up to 24 hours:
    /// near J2000 the pole of date is arcseconds from the J2000 pole and its
    /// right ascension turns through every hour.
    @Test("Earth's right ascension stays in 0 to 24 hours before and after J2000")
    func earthRightAscension() throws {
        var signs = Set<Bool>()
        for tt in Self.times + [9_303.0] {
            let axis = try Axes.axis(of: .earth, at: Self.time(tt: tt))
            #expect((0..<24).contains(axis.rightAscension), "tt \(tt)")
            signs.insert(tt > 0)
        }
        #expect(signs == [false, true])
    }

    /// Earth's W turns at the Earth rotation angle's rate on UT1: against
    /// SOFA's `era00` at UT1 for the same eight epochs, W less the angle is
    /// the same, `earthSpinAtJ2000` less the angle's 280.46061837504° at UT1
    /// 0, modulo 360°.
    @Test("Earth's W is the Earth rotation angle on UT, offset")
    func earthSpinRate() throws {
        #expect(abs(Axes.earthSpinRate - 360 * 1.002_737_811_911_354_48) <= 1e-12)
        let offset = Axes.earthSpinAtJ2000 - 360 * 0.779_057_273_264_0
        for reference in PublishedOrientation.references {
            let axis = try Axes.axis(of: .earth, at: EngineFrameRotationTests.time(reference))
            let rotation = reference.era00 * Engine.degreesPerRadian
            let difference = (axis.spin - rotation - offset).truncatingRemainder(dividingBy: 360)
            #expect(min(abs(difference), 360 - abs(difference)) <= Self.allowance(axis.spin), "\(reference.year)")
        }
        // The same W at TT would be off by Delta T, over a minute in 2026: over 0.25°.
        let now = Self.time(tt: 9_496)
        #expect(now.tt - now.ut > 60 / Engine.secondsPerDay)
        let earth = try Axes.axis(of: .earth, at: now)
        let atTT = Axes.earthSpinAtJ2000 + Axes.earthSpinRate * now.tt
        #expect(abs(earth.spin - atTT) > 0.25)
    }

    /// Earth's W at J2000 equals the 2009 report's, `BODY399_PM` in the PCK,
    /// moved onto UT: the Delta T it implies is within the 0.1 s to which the
    /// Astronomical Almanac's observed Delta T for 2000.0, 63.8 s, is
    /// published (`PublishedDeltaT.observedTable`). So at J2000 TT, with UT
    /// 63.8 s earlier, the report's pole and Earth's W place the report's
    /// prime meridian within that 0.1 s of rotation, 1.5″. Only there: the
    /// two W turn at different rates, on UT and on TDB.
    @Test("Earth's W is the report's at J2000, re-expressed on UT")
    func earthSpinOrigin() throws {
        let report = try Self.published(399, tdb: 0)
        let implied = (Axes.earthSpinAtJ2000 - report.spin) / Axes.earthSpinRate * Engine.secondsPerDay
        let observed = try #require(PublishedDeltaT.observedTable.first { $0.year == 2000 })
        #expect(abs(implied - observed.seconds) <= observed.bound)
        let time = Engine.Time(ut: -observed.seconds / Engine.secondsPerDay, tt: 0, deltaTModel: .espenakMeeus)
        let axis = try Axes.axis(of: .earth, at: time)
        let placed = Self.primeMeridian(ra: report.ra, dec: report.dec, spin: axis.spin)
        let published = Self.primeMeridian(ra: report.ra, dec: report.dec, spin: report.spin)
        let rotation = Axes.earthSpinRate * observed.bound / Engine.secondsPerDay * 3600
        #expect(Self.arcseconds(placed, published) <= rotation)
    }

    /// Greenwich, where the true equator of date meets the meridian at
    /// apparent sidereal time, against the prime meridian Earth's returned
    /// pole and W place by the construction the other bodies follow. Near
    /// J2000 the true pole's right ascension, from which that construction
    /// starts, turns through every hour, so the two need not be close.
    @Test("Earth's returned pole and W do not place Greenwich")
    func earthGreenwich() throws {
        for tt in [-36_524.5, -0.5, 9_496.5, 36_525.5] {
            let time = Self.time(tt: tt)
            let axis = try Axes.axis(of: .earth, at: time)
            let placed = Self.primeMeridian(ra: axis.rightAscension * 15, dec: axis.declination, spin: axis.spin)
            let gast = Engine.EarthRotation.apparentSiderealTime(time) * 15 * Engine.radiansPerDegree
            let greenwich = Engine.FrameRotation.eqdToEqj(time).apply(to: SIMD3(cos(gast), sin(gast), 0))
            #expect(Self.arcseconds(placed, greenwich) > 0.25 * 3600, "tt \(tt)")
        }
    }

    // MARK: - Guards

    @Test("Bodies the reports do not cover throw invalidBody, before anything else")
    func invalidBodies() {
        for body in CelestialBody.allCases where !Axes.bodies.contains(body) {
            #expect(throws: AstronomyError.invalidBody) { try Axes.axis(of: body, at: Self.time(tt: 0)) }
            #expect(throws: AstronomyError.invalidBody) { try Axes.axis(of: body, at: Self.time(tt: .nan)) }
        }
        #expect(Set(Axes.bodies) == Set(Self.naifIDs.keys))
    }

    @Test("Times that are not finite throw badTime", arguments: Axes.bodies)
    func nonFiniteTimes(body: CelestialBody) {
        for tt in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.badTime) { try Axes.axis(of: body, at: Self.time(tt: tt)) }
        }
    }

    @Test("Results carry the time they were given")
    func resultTime() throws {
        let time = Engine.Time(ut: 9_496.25, deltaTModel: .espenakMeeus)
        for body in Axes.bodies {
            let axis = try Axes.axis(of: body, at: time)
            #expect(axis.north.time.ut == time.ut && axis.north.time.tt == time.tt, "\(body)")
        }
    }
}

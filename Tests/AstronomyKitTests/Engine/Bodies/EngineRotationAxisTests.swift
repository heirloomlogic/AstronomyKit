//
//  EngineRotationAxisTests.swift
//  AstronomyKit
//
//  Rotation axes against the IAU WGCCRE elements as NAIF's PCK publishes
//  them, Earth's against the IAU 2006/2000B orientation, and the guards.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.RotationAxis")
struct EngineRotationAxisTests {
    typealias Axes = Engine.RotationAxis

    static func time(tt: Double) -> Engine.Time { PlanetTestSupport.time(tt: tt) }

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
        let ra = try variable("BODY\(id)_POLE_RA")
        let dec = try variable("BODY\(id)_POLE_DEC")
        let pm = try variable("BODY\(id)_PM")
        var result = (
            ra: ra[0] + ra[1] * t + ra[2] * t * t, dec: dec[0] + dec[1] * t + dec[2] * t * t,
            spin: pm[0] + pm[1] * d + pm[2] * d * d
        )
        guard let angles = pck["BODY\(id / 100)_NUT_PREC_ANGLES"], id > 100 else { return result }
        let degree = Int(pck["BODY\(id / 100)_MAX_PHASE_DEGREE"]?.first ?? 1)
        let theta = stride(from: 0, to: angles.count, by: degree + 1).map { start in
            (0...degree).reduce(0.0) { sum, power in sum + angles[start + power] * pow(t, Double(power)) }
                * Engine.radiansPerDegree
        }
        for (i, a) in (pck["BODY\(id)_NUT_PREC_RA"] ?? []).enumerated() { result.ra += a * sin(theta[i]) }
        for (i, a) in (pck["BODY\(id)_NUT_PREC_DEC"] ?? []).enumerated() { result.dec += a * cos(theta[i]) }
        for (i, a) in (pck["BODY\(id)_NUT_PREC_PM"] ?? []).enumerated() { result.spin += a * sin(theta[i]) }
        return result
    }

    /// The allowance for evaluating the same expressions in another order:
    /// up to 27 terms each rounded once, so 1e-14 (45 roundings) of the
    /// magnitude, plus a turn's worth for angles near zero.
    static func allowance(_ value: Double) -> Double { 1e-14 * (abs(value) + 360) }

    /// 81 times a century apart across the accepted range, both ends
    /// included, and 61 times 13.37 days apart from 2026-01-01 into 2028,
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

    @Test(
        "Every body but Earth matches the WGCCRE elements of pck00011.tpc",
        arguments: Axes.bodies.filter { $0 != .earth })
    func publishedElements(body: CelestialBody) throws {
        let id = try #require(Self.naifIDs[body])
        for tt in Self.times {
            let axis = try Axes.axis(of: body, at: Self.time(tt: tt))
            let expected = try Self.published(id, tdb: Self.tdb(tt: tt))
            #expect(abs(axis.rightAscension * 15 - expected.ra) <= Self.allowance(expected.ra), "tt \(tt)")
            #expect(abs(axis.declination - expected.dec) <= Self.allowance(expected.dec), "tt \(tt)")
            #expect(abs(axis.spin - expected.spin) <= Self.allowance(expected.spin), "tt \(tt)")
            let north = Engine.Vector<Engine.EQJ>(
                Engine.Spherical(latitude: expected.dec, longitude: expected.ra, distance: 1), time: .invalid)
            let allowed = 3600 * (Self.allowance(expected.ra) + Self.allowance(expected.dec))
            #expect(Self.arcseconds(Self.vector(axis.north), Self.vector(north)) <= allowed, "tt \(tt)")
        }
    }

    /// At the sample time where TDB − TT is largest, over 1 ms, Jupiter's W
    /// moves by over 1e-5°; the elements evaluated at TT, or for another body,
    /// fail.
    @Test("The check fails for TT taken as TDB or for the wrong body")
    func negativeControls() throws {
        let offsets = Self.times.map { (tt: $0, seconds: abs(Engine.TDB.offsetSeconds(tt: $0))) }
        let largest = try #require(offsets.max { $0.seconds < $1.seconds })
        let late = largest.tt
        #expect(largest.seconds > 1e-3)
        let axis = try Axes.axis(of: .jupiter, at: Self.time(tt: late))
        let atTT = try Self.published(599, tdb: late)
        #expect(abs(axis.spin - atTT.spin) > Self.allowance(atTT.spin))
        let saturn = try Self.published(699, tdb: Self.tdb(tt: late))
        #expect(abs(axis.declination - saturn.dec) > Self.allowance(saturn.dec))
    }

    // MARK: - Earth

    /// 1800 to 2200 every 20 years, both ends included.
    static let earthTimes = Array(stride(from: -73_050.0, through: 73_050, by: 7_305))

    @Test("Earth's pole is the true pole of date, rotated to J2000")
    func earthPole() throws {
        #expect(Self.earthTimes.first == -73_050 && Self.earthTimes.last == 73_050)
        for tt in Self.times + Self.earthTimes {
            let time = Self.time(tt: tt)
            let axis = try Axes.axis(of: .earth, at: time)
            let pole = Engine.FrameRotation.eqdToEqj(time).apply(to: SIMD3(0.0, 0, 1))
            #expect(Self.vector(axis.north) == pole, "tt \(tt)")
            let equatorial = try Engine.Equatorial(axis.north)
            #expect(axis.rightAscension == equatorial.rightAscension && axis.declination == equatorial.declination)
        }
    }

    /// The 2009 report's Earth pole, `BODY399` in the PCK, is linear in T.
    /// The mean pole of date (precession without nutation) is at
    /// θA = 2004.191903″T − 0.4294934″T² − 0.04182264″T³ from the J2000 pole
    /// (Capitaine et al. 2003, the IAU 2006 precession), and the report puts
    /// it at 0.557°T = 2005.2″T; its right ascension, −0.641°T against
    /// −ζA = −2306.083227″T − 0.2988499″T² − 0.01801828″T³, moves it sideways
    /// by θA times that difference, under 0.1″ over these dates, and the
    /// frame bias between EQJ and the ICRF is 0.02″.
    @Test("Earth's mean pole stays within the precession the report's Earth pole leaves out, 1800 to 2200")
    func earthReportPole() throws {
        for tt in Self.earthTimes {
            let t = abs(tt) / 36_525
            let tdb = Self.tdb(tt: tt)
            let pck = try Self.published(399, tdb: tdb)
            let report = Engine.Vector<Engine.EQJ>(
                Engine.Spherical(latitude: pck.dec, longitude: pck.ra, distance: 1), time: .invalid)
            let (ra, dec) = Axes.reportEarthPole(tdb: tdb)
            #expect(abs(ra - pck.ra) <= Self.allowance(pck.ra) && abs(dec - pck.dec) <= Self.allowance(pck.dec))
            let mean = Engine.Precession.rotation(tt: tt).inverse.apply(to: SIMD3(0.0, 0, 1))
            let bound = 1.0081 * t + 0.4295 * t * t + 0.0419 * t * t * t + 0.1 + 0.02
            #expect(Self.arcseconds(mean, Self.vector(report)) <= bound, "tt \(tt)")
        }
    }

    /// Greenwich, where the true equator of date meets the meridian at
    /// apparent sidereal time, against the meridian the report's Earth pole
    /// and the engine's W place. The report's pole is off the true one by
    /// nutation and the precession above, which tilts the meridian by at most
    /// their angle. Measuring W from the report pole's node instead of along
    /// the true equator adds at most θ²/2 for a tilt θ = 0.557°T, 9.75″T².
    @Test("Earth's spin places Greenwich, 1800 to 2200")
    func earthSpin() throws {
        for tt in Self.earthTimes {
            let time = Self.time(tt: tt)
            let axis = try Axes.axis(of: .earth, at: time)
            let tdb = Self.tdb(tt: tt)
            let (ra, dec) = Axes.reportEarthPole(tdb: tdb)
            let rad = Engine.radiansPerDegree
            // The body-fixed x axis: rotate by W about the pole, tilt the pole
            // down from z by 90° − δ0, then turn the node to 90° + α0.
            let (cw, sw) = (cos(axis.spin * rad), sin(axis.spin * rad))
            let (ct, st) = (cos((90 - dec) * rad), sin((90 - dec) * rad))
            let (cn, sn) = (cos((90 + ra) * rad), sin((90 + ra) * rad))
            let tilted = SIMD3(cw, sw * ct, sw * st)
            let meridian = SIMD3(tilted.x * cn - tilted.y * sn, tilted.x * sn + tilted.y * cn, tilted.z)
            let gast = Engine.EarthRotation.apparentSiderealTime(time) * 15 * rad
            let greenwich = Engine.FrameRotation.eqdToEqj(time).apply(to: SIMD3(cos(gast), sin(gast), 0))
            let report = Engine.Vector<Engine.EQJ>(
                Engine.Spherical(latitude: dec, longitude: ra, distance: 1), time: .invalid)
            let tilt = Self.arcseconds(Self.vector(axis.north), Self.vector(report))
            let t = tt / 36_525
            #expect(Self.arcseconds(meridian, greenwich) <= tilt + 9.75 * t * t + 0.1, "tt \(tt)")
        }
    }

    @Test("Earth's spin is the Earth rotation angle less 90° and the report pole's right ascension")
    func earthSpinDefinition() throws {
        for tt in Self.times {
            let time = Self.time(tt: tt)
            let axis = try Axes.axis(of: .earth, at: time)
            let expected = Engine.EarthRotation.angle(ut: time.ut) - 90 - Axes.reportEarthPole(tdb: Self.tdb(tt: tt)).ra
            let difference = (axis.spin - expected).truncatingRemainder(dividingBy: 360)
            let turns = min(abs(difference), 360 - abs(difference))
            #expect(turns <= Self.allowance(axis.spin), "tt \(tt)")
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

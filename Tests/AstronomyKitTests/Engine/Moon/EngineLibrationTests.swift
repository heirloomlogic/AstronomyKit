//
//  EngineLibrationTests.swift
//  AstronomyKit
//
//  Libration against NASA's published tables, and the lunar inputs to the
//  phase, apsis and node searches against the published event tables.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine Moon libration and event inputs")
struct EngineLibrationTests {
    /// One hourly row of a NASA Scientific Visualization Studio "Moon Phase
    /// and Libration" table.
    struct Row: Sendable, CustomTestStringConvertible {
        let line: Int
        /// The row's date and time, as the table prints them.
        let stamp: String
        let ut: Double
        let diameterArcseconds: Double
        let distanceKilometers: Double
        let longitude: Double
        let latitude: Double

        var testDescription: String { "line \(line): \(stamp)" }
    }

    /// A row or file of the tables that does not read as expected.
    struct TableError: Error, CustomStringConvertible {
        let description: String
    }

    /// `mooninfo_2020.txt` to `mooninfo_2022.txt`, copied unchanged from
    /// Astronomy Engine at the revision `build-fixtures.py` pins, which
    /// checks their SHA-256. Columns: date, time, phase, age, diameter (″),
    /// distance (km), RA, Dec, sub-solar longitude and latitude, sub-Earth
    /// longitude and latitude (the libration, in degrees), axis angle.
    /// A file or row that does not parse fails the tests that read it.
    static let rows = Result { () throws -> [Int: [Row]] in
        let directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // Moon
            .deletingLastPathComponent()  // Engine
            .deletingLastPathComponent()  // AstronomyKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/reference-data/sources")
        var tables: [Int: [Row]] = [:]
        for year in 2020...2022 {
            let url = directory.appendingPathComponent("mooninfo_\(year).txt")
            let text = try String(contentsOf: url, encoding: .utf8)
            tables[year] = try text.split(separator: "\n").enumerated().dropFirst().map { index, line in
                try row(line: index + 1, text: line)
            }
        }
        return tables
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// One row of a table: `line` is its 1-based line in the file.
    static func row(line: Int, text: Substring) throws -> Row {
        let f = text.split(separator: " ")
        guard f.count > 14 else { throw TableError(description: "line \(line): \(f.count) fields") }
        let clock = f[3].split(separator: ":").compactMap { Int($0) }
        guard let day = Int(f[0]), let month = months.firstIndex(of: String(f[1])), let year = Int(f[2]),
            clock.count >= 2,
            let diameter = Double(f[7]), let distance = Double(f[8]), let longitude = Double(f[13]),
            let latitude = Double(f[14])
        else { throw TableError(description: "line \(line): unreadable row \"\(text)\"") }
        let ut = Engine.Time.days(year: year, month: month + 1, day: day, hour: clock[0], minute: clock[1], second: 0)
        return Row(
            line: line, stamp: String(text.prefix(17)), ut: ut, diameterArcseconds: diameter,
            distanceKilometers: distance, longitude: longitude, latitude: latitude)
    }

    /// Astronomy Engine's limits for these tables (`ctest.c`, `Libration`),
    /// except latitude.
    static let longitudeArcminutes = 0.1304
    static let distanceKilometers = 54.377
    static let diameterDegrees = 0.00009
    /// The largest latitude difference over the three tables, 1.6692′ at
    /// 2020-01-12 08:00 UT, rounded up. About 1.40′ of it is a steady offset
    /// of Meeus's formulas from NASA's. Astronomy Engine's 1.6476′ was set
    /// for its lunar series and its 1.543° inclination.
    static let latitudeArcminutes = 1.67

    @Test(
        "Libration, distance and diameter within their limits on every hourly row",
        arguments: [2020, 2021, 2022])
    func againstNASA(year: Int) throws {
        let rows = try #require(try Self.rows.get()[year])
        #expect(rows.count == (year == 2020 ? 8_785 : 8_760))
        // Every row is a new instant, so a private cache keeps them out of the shared one.
        let (cache, _) = EngineMoonCacheTests.makeCache()
        for row in rows {
            // The tables give UT; the harness takes Espenak-Meeus Delta T.
            let time = Engine.Time(ut: row.ut, deltaTModel: .espenakMeeus)
            let libration = Engine.Moon.libration(at: time, cache: cache)
            #expect(abs(libration.longitude - row.longitude) * 60 <= Self.longitudeArcminutes, "\(row.testDescription)")
            #expect(abs(libration.distanceKilometers - row.distanceKilometers) <= Self.distanceKilometers)
            #expect(abs(libration.diameter - row.diameterArcseconds / 3_600) <= Self.diameterDegrees)
            let latitude = abs(libration.latitude - row.latitude) * 60
            #expect(latitude <= Self.latitudeArcminutes, "\(row.testDescription): \(latitude)′")
        }
    }

    @Test("The checks fail an hour off, with longitude and latitude swapped, or in AU")
    func negativeControls() throws {
        let row = try #require(try Self.rows.get()[2021]?[100])
        let late = Engine.Moon.libration(at: Engine.Time(ut: row.ut + 1.0 / 24, deltaTModel: .espenakMeeus))
        #expect(abs(late.longitude - row.longitude) * 60 > Self.longitudeArcminutes)
        let libration = Engine.Moon.libration(at: Engine.Time(ut: row.ut, deltaTModel: .espenakMeeus))
        #expect(abs(libration.latitude - row.longitude) * 60 > Self.latitudeArcminutes)
        let au = libration.distanceKilometers / Engine.kilometersPerAU
        #expect(abs(au - row.distanceKilometers) > Self.distanceKilometers)
    }

    @Test("The Moon's position fields are the model's, in degrees and km")
    func positionFields() {
        for tt in [-1_000_000.25, -36_530.0, 0, 9_497.375, 47_860.0, 700_000.5] {
            let time = PlanetTestSupport.time(tt: tt)
            let libration = Engine.Moon.libration(at: time)
            let model = Engine.Moon.coordinates(centuries: tt / 36_525)
            #expect(libration.moonLongitude == Engine.degreesPerRadian * model.x)
            #expect(libration.moonLatitude == Engine.degreesPerRadian * model.y)
            #expect(libration.distanceKilometers == model.z * Engine.kilometersPerAU)
            #expect(libration.longitude > -180 && libration.longitude <= 180, "tt \(tt)")
        }
    }

    @Test("Libration reads one cached epoch, shared with the positions")
    func cache() throws {
        let (cache, _) = EngineMoonCacheTests.makeCache()
        let time = PlanetTestSupport.time(tt: 200_000.25)
        _ = Engine.Moon.libration(at: time, cache: cache)
        _ = try Engine.Moon.geocentricPosition(at: time, cache: cache)
        _ = try Engine.Moon.distance(at: time, cache: cache)
        #expect(cache.statistics == EngineMoonCacheTests.Statistics(hits: 2, misses: 1))
    }

    @Test("A time that is not finite gives NaN, as in the C engine", arguments: [Double.nan, .infinity, -.infinity])
    func notFinite(tt: Double) {
        let libration = Engine.Moon.libration(at: Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus))
        let fields = [
            libration.latitude, libration.longitude, libration.moonLatitude, libration.moonLongitude,
            libration.distanceKilometers, libration.diameter,
        ]
        let allNaN = fields.allSatisfy { $0.isNaN }
        #expect(allNaN)
    }

    @Test("Longitudes move into range as the C engine's helpers move them")
    func longitudeHelpers() {
        #expect(Engine.normalizedLongitude(-30) == 330)
        #expect(Engine.normalizedLongitude(720.25) == 0.25)
        #expect(Engine.normalizedLongitude(-720) == 0 && Engine.normalizedLongitude(-720).sign == .plus)
        #expect(Engine.normalizedLongitude(-0.0).sign == .minus)
        #expect(Engine.longitudeOffset(190) == -170)
        #expect(Engine.longitudeOffset(-180) == 180)
        #expect(Engine.longitudeOffset(180) == 180)
        #expect(Engine.longitudeOffset(1e17).isFinite)
        #expect(Engine.normalizedLongitude(.infinity).isNaN && Engine.longitudeOffset(.nan).isNaN)
    }

    // MARK: - Event inputs

    static func time(_ utc: String) -> Engine.Time {
        Engine.Time(ut: IndependentReferenceDate.civil(utc).universalTime, deltaTModel: .espenakMeeus)
    }

    /// The Sun's longitude on the true ecliptic of date as the C engine's
    /// `Astronomy_MoonPhase` finds it: the Sun at the heliocentric origin,
    /// seen from Earth's center at `time`, with no aberration.
    static func sunLongitude(at time: Engine.Time) throws -> Double {
        let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
        return Engine.Ecliptic(Engine.Vector(x: -earth.x, y: -earth.y, z: -earth.z, time: time)).longitude
    }

    /// USNO's quarter times, as Astronomy Engine tabulates them. Its
    /// `ctest.c` (`MoonPhase`) requires the phase angle at each to be within
    /// 1′ of the quarter; the times are printed to the minute, which is up
    /// to 0.25′ of the Moon's motion against the Sun.
    @Test("The Moon's ecliptic longitude gives USNO's quarters within 1′ of phase")
    func quarters() throws {
        let phases = IndependentReferenceArchive.shared.lunarPhases
        #expect(phases.count == 12)
        let quarters = ["new": 0.0, "firstQuarter": 90, "full": 180, "lastQuarter": 270]
        for phase in phases {
            let time = Self.time(phase.sourceTime)
            let angle = Engine.normalizedLongitude(
                try Engine.Moon.eclipticLongitude(at: time) - Self.sunLongitude(at: time))
            let error = abs(Engine.longitudeOffset(angle - (try #require(quarters[phase.phase])))) * 60
            #expect(error <= 1, "\(phase.sourceTime) \(phase.phase): \(error)′")
        }
    }

    @Test("The model's distance at the published lunar apsides within their 25 km")
    func apsides() throws {
        let apsides = IndependentReferenceArchive.shared.lunarApsides
        #expect(apsides.count == 6)
        for apsis in apsides {
            let km = try Engine.Moon.distance(at: Self.time(apsis.utc)) * Engine.kilometersPerAU
            let expected = try #require(apsis.distanceKM)
            #expect(abs(km - expected) <= (try #require(apsis.distanceToleranceKM)), "\(apsis.utc): \(km) km")
        }
    }

    /// Espenak's node times carry a 220.86 s limit in Astronomy Engine's
    /// harness, so at each the latitude can be off zero by at most its rate
    /// times that.
    @Test("The ecliptic latitude at Espenak's node times is zero within the time limit")
    func nodes() throws {
        let nodes = IndependentReferenceArchive.shared.lunarNodes
        #expect(nodes.count == 6)
        for node in nodes {
            let state = try Engine.Moon.eclipticState(at: Self.time(node.utc))
            let allowance = abs(state.latitudeRate) * node.timeToleranceSeconds / Engine.secondsPerDay
            #expect(abs(state.latitude) <= allowance, "\(node.utc): \(state.latitude)°")
            #expect((state.latitudeRate > 0) == (node.kind == "ascending"), "\(node.utc)")
        }
    }

    @Test("The event inputs reject times outside the accepted range")
    func eventInputRange() {
        for tt in [Engine.acceptedTTDays.nextUp, .nan] {
            let time = PlanetTestSupport.time(tt: tt)
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.eclipticLongitude(at: time) }
            #expect(throws: AstronomyError.badTime) { try Engine.Moon.distance(at: time) }
        }
    }
}

//
//  EngineIlluminationTests.swift
//  AstronomyKit
//
//  Magnitudes, phase angles, Saturn's ring tilt, elongations and pair
//  longitudes against JPL Horizons, and their composition and errors.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine illumination and separations")
struct EngineIlluminationTests {
    typealias Positions = Engine.Positions

    static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // Positions
        .deletingLastPathComponent()  // Engine
        .deletingLastPathComponent()  // AstronomyKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()
        .appendingPathComponent("Scripts/reference-data/sources")

    /// A row of a Horizons magnitude table: UT, apparent magnitude, the
    /// distance from the Sun `r` in AU and its rate `rdot` in km/s, the
    /// distance from Earth `delta` in AU, and the phase angle `S-T-O`.
    struct MagnitudeRow {
        let time: Engine.Time
        let label: String
        let magnitude: Double
        let heliocentricDistance: Double
        let heliocentricDistanceRate: Double
        let geocentricDistance: Double
        let phaseAngle: Double
    }

    static let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    /// The rows of `magnitude_<body>.txt` that hold values, skipping `n.a.`
    /// ones. Horizons' times are UTC; the TT comes from the leap-second
    /// table, since the Espenak-Meeus Delta T runs up to about 6 s ahead
    /// of it by 2030, which moves Mercury tens of kilometres.
    static func magnitudeRows(_ body: CelestialBody) throws -> [MagnitudeRow] {
        let url = sources.appendingPathComponent("magnitude_\(body.name.lowercased()).txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        let table = try #require(text.components(separatedBy: "$$SOE").last?.components(separatedBy: "$$EOE").first)
        return try table.split(separator: "\n").compactMap { line in
            guard !line.contains("n.a.") else { return nil }
            let fields = line.split(separator: " ")
            let date = fields[0].split(separator: "-")
            let clock = fields[1].split(separator: ":")
            let month = try #require(months.firstIndex(of: String(date[1]))) + 1
            let ut = Engine.Time.days(
                year: Int(date[0])!, month: month, day: Int(date[2])!, hour: Int(clock[0])!, minute: Int(clock[1])!,
                second: 0)
            let values = fields[2...].map { Double($0)! }
            return MagnitudeRow(
                time: Engine.Time.civil(utcDays: ut, deltaTModel: .espenakMeeus).time, label: "\(body) \(fields[0])",
                magnitude: values[0], heliocentricDistance: values[2], heliocentricDistanceRate: values[3],
                geocentricDistance: values[4], phaseAngle: values[6])
        }
    }

    static let tableBodies: [CelestialBody] = [
        .sun, .moon, .mercury, .venus, .mars, .jupiter, .uranus, .neptune, .pluto,
    ]

    /// Horizons' magnitudes from 2010 to 2030, every two days, as Astronomy
    /// Engine pins them, within the 0.012 its `MagnitudeTest` (`ctest.c`)
    /// allows. The same rows give the phase angle and the distance from the
    /// Sun, which Horizons takes with the body where it was when light left
    /// it, τ = delta / c earlier, and the engine, like the C engine, where it
    /// is at the observation time. Each row allows what the body's motion in
    /// τ can change: for the distance |rdot|·τ, plus the allowance
    /// `DistanceAccuracyTests` gives the body's distance from the Sun (for the
    /// Moon, Earth's and the Moon's from Earth) and the Sun's own motion over
    /// the light time from it; for the phase angle the turn
    /// of the lines to the Sun and to Earth, v·τ·(1/r + 1/delta) with v the
    /// body's heliocentric speed, plus aberration (below); both plus the
    /// rows' printed precision.
    @Test("Magnitudes, phase angles and distances from the Sun against Horizons", arguments: tableBodies)
    func magnitudeTables(body: CelestialBody) throws {
        let rows = try Self.magnitudeRows(body)
        #expect(rows.count >= 3_560)
        for row in rows {
            let illumination = try Positions.illumination(of: body, at: row.time)
            #expect(abs(illumination.magnitude - row.magnitude) <= 0.012, "\(row.label): \(illumination.magnitude)")
            let lightTime = row.geocentricDistance / Engine.speedOfLightAUPerDay
            let rate = abs(row.heliocentricDistanceRate) * Engine.secondsPerDay / Engine.kilometersPerAU
            // Horizons also takes the Sun where it was when light left it for
            // the body, which moves it about the barycenter at under 15 m/s,
            // 8.7e-6 AU per day.
            let sunMotion = 8.7e-6 * row.heliocentricDistance / Engine.speedOfLightAUPerDay
            let modelAllowance = try Self.distanceAllowanceAU(body) + sunMotion
            #expect(
                abs(illumination.heliocentricDistance - row.heliocentricDistance)
                    <= rate * lightTime + modelAllowance + 5e-13,
                "\(row.label): \(illumination.heliocentricDistance)")
            guard body != .sun else { continue }
            // Horizons takes the line to Earth as seen from Earth, with
            // aberration, which turns it by up to κ = 20.49552″.
            let aberration = 20.49552 / 3_600
            let speed = EngineGravityTests.length(
                try Positions.heliocentricState(of: body, at: row.time).velocityVector)
            let turn = speed * lightTime * (1 / row.heliocentricDistance + 1 / row.geocentricDistance)
            #expect(
                abs(illumination.phaseAngle - row.phaseAngle) <= turn * Engine.degreesPerRadian + aberration + 5e-5,
                "\(row.label): \(illumination.phaseAngle)")
        }
    }

    /// The `distance-fixtures.json` allowance for `body`'s distance from the
    /// Sun in AU: 0 for the Sun, Earth's plus the Moon's geocentric one for
    /// the Moon.
    static func distanceAllowanceAU(_ body: CelestialBody) throws -> Double {
        func allowance(_ name: String, _ mode: String) throws -> Double {
            try #require(
                DistanceReferenceArchive.shared.references.first { $0.body == name && $0.mode == mode }
            ).allowedErrorKm / Engine.kilometersPerAU
        }
        switch body {
        case .sun: return 0
        case .moon: return try allowance("Earth", "heliocentric") + allowance("Moon", "geocentric")
        default: return try allowance(body.name, "heliocentric")
        }
    }

    @Test("The magnitude check fails for the wrong body and a day off")
    func magnitudeNegativeControls() throws {
        let row = try #require(try Self.magnitudeRows(.mars).first)
        #expect(abs(try Positions.illumination(of: .jupiter, at: row.time).magnitude - row.magnitude) > 0.012)
        let late = try Positions.illumination(of: .mars, at: row.time.adding(days: 1))
        #expect(abs(late.magnitude - row.magnitude) > 0.012 || abs(late.phaseAngle - row.phaseAngle) > 0.02)
    }

    /// Horizons gives Saturn's planetodetic sub-observer latitude on its
    /// ellipsoid. The ring tilt is the planetocentric one, the latitude of
    /// the line of sight to Earth above Saturn's equator and rings,
    /// tan βc = (b/a)² tan βd, with the C engine's sign: positive when Earth
    /// is south of the ring plane. The engine's ring plane is Paul
    /// Schlyter's fixed approximation, so the allowance, 0.02°, is a measured
    /// bound rounded up (measured 0.015°), not a published accuracy. The
    /// phase angle has the allowance of the magnitude tables, under 0.02°
    /// for Saturn. Saturn's magnitude has no published check: Horizons leaves
    /// the rings out of it.
    @Test("Saturn's ring tilt and phase angle against Horizons")
    func saturnRings() throws {
        let rows = IndependentReferenceArchive.shared.saturnRings
        #expect(rows.count == 11)
        var signs = Set<Bool>()
        for row in rows {
            let illumination = try Positions.illumination(of: .saturn, at: IndependentReferenceDate.engine(row.utc))
            let ratio = row.polarRadiusKm / row.equatorialRadiusKm
            let planetodetic = row.subObserverPlanetodeticLatitudeDegrees * Engine.radiansPerDegree
            let tilt = atan(ratio * ratio * tan(planetodetic)) * Engine.degreesPerRadian
            #expect(abs(illumination.ringTilt + tilt) <= 0.02, "\(row.utc): \(illumination.ringTilt)° vs \(-tilt)°")
            #expect(abs(illumination.phaseAngle - row.phaseAngleDegrees) <= 0.02, "\(row.utc)")
            signs.insert(tilt > 0)
        }
        // The dates straddle the 2025 ring-plane crossing.
        #expect(signs == [true, false])
    }

    // MARK: - Elongation and pair longitude

    static let elongations = IndependentReferenceArchive.shared.elongations

    static func body(_ name: String) throws -> CelestialBody {
        try PlutoSegmentSuites.EngineObserverRowTests.body(name)
    }

    /// Horizons' S-O-T is the apparent elongation, printed to 0.0001°, and
    /// `/T` marks a body trailing the Sun, in the evening sky. The engine's
    /// Moon gets no aberration, as in the public API, so the allowance is the
    /// position tolerance of the observer rows, 1′.
    @Test("Elongations and their sides against Horizons")
    func elongation() throws {
        #expect(Self.elongations.count == 40)
        var sides = Set<Visibility>()
        for row in Self.elongations {
            let body = try Self.body(row.body)
            let elongation = try Positions.elongation(of: body, at: IndependentReferenceDate.engine(row.utc))
            let label = "\(row.body) \(row.utc)"
            #expect(abs(elongation.elongation - row.elongationDegrees) * 60 <= 1, "\(label): \(elongation.elongation)°")
            #expect(elongation.visibility == (row.trailsSun ? .evening : .morning), "\(label)")
            sides.insert(elongation.visibility)
        }
        #expect(sides == [.morning, .evening])
    }

    /// The difference of two bodies' apparent ecliptic longitudes from the
    /// same Horizons rows. The engine's pair longitude has no aberration, so
    /// each longitude can differ by up to κ = 20.5″ and the pair by twice
    /// that; the allowance is 1′.
    @Test("Pair longitudes against the difference of Horizons' ecliptic longitudes")
    func pairLongitude() throws {
        let byDate = Dictionary(grouping: Self.elongations, by: \.utc)
        #expect(byDate.count == 8)
        for (utc, rows) in byDate {
            for first in rows {
                for second in rows where second.body != first.body {
                    let pair = try Positions.pairLongitude(
                        try Self.body(first.body), try Self.body(second.body), at: IndependentReferenceDate.engine(utc))
                    let published = Engine.normalizedLongitude(
                        first.eclipticLongitudeDegrees - second.eclipticLongitudeDegrees)
                    let arcminutes = abs(IndependentReferenceMath.wrappedDifference(pair, published)) * 60
                    #expect(arcminutes <= 1, "\(first.body) − \(second.body) \(utc): \(arcminutes)′")
                }
            }
        }
    }

    // MARK: - Composition and errors

    static let instant = Engine.Time(tt: 9_500.75, deltaTModel: .espenakMeeus)

    @Test("Elongation, angle from the Sun and pair longitude are composed from the geocentric positions")
    func composition() throws {
        for body: CelestialBody in [.moon, .mercury, .venus, .mars, .saturn, .pluto] {
            let sun = try Positions.geocentricPosition(of: .sun, at: Self.instant, aberration: .corrected)
            let target = try Positions.geocentricPosition(of: body, at: Self.instant, aberration: .corrected)
            let angle = try Positions.angleFromSun(of: body, at: Self.instant)
            #expect(angle == (try sun.angle(to: target)), "\(body)")
            let pair = try Positions.pairLongitude(body, .sun, at: Self.instant)
            let elongation = try Positions.elongation(of: body, at: Self.instant)
            #expect(elongation.elongation == angle)
            #expect(elongation.eclipticSeparation == (pair > 180 ? 360 - pair : pair))
            #expect((0..<360).contains(pair))
            let reverse = try Positions.pairLongitude(.sun, body, at: Self.instant)
            #expect(abs(IndependentReferenceMath.wrappedDifference(pair + reverse, 0)) < 1e-9, "\(body)")
        }
    }

    @Test("Illumination is the C engine's composition: phase from the geometric vectors, fraction from the phase")
    func illuminationComposition() throws {
        let earth = try Positions.heliocentricPosition(of: .earth, at: Self.instant)
        for body: CelestialBody in [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto] {
            let illumination = try Positions.illumination(of: body, at: Self.instant)
            let heliocentric = try Positions.heliocentricPosition(of: body, at: Self.instant)
            let geocentric = Engine.Vector<Engine.EQJ>(
                x: heliocentric.x - earth.x, y: heliocentric.y - earth.y, z: heliocentric.z - earth.z,
                time: Self.instant)
            #expect(illumination.phaseAngle == (try geocentric.angle(to: heliocentric)), "\(body)")
            #expect(illumination.heliocentricDistance == heliocentric.length)
            let fraction = (1 + cos(illumination.phaseAngle * Engine.radiansPerDegree)) / 2
            #expect(illumination.phaseFraction == fraction)
            #expect(illumination.ringTilt == 0 || body == .saturn)
        }
        let sun = try Positions.illumination(of: .sun, at: Self.instant)
        #expect(sun.phaseAngle == 0 && sun.phaseFraction == 1 && sun.heliocentricDistance == 0)
    }

    @Test("Earth is not allowed, unsupported bodies and times throw")
    func errors() {
        let outside = Engine.Time(tt: Engine.acceptedTTDays * 2, deltaTModel: .espenakMeeus)
        #expect(throws: AstronomyError.earthNotAllowed) { try Positions.illumination(of: .earth, at: outside) }
        #expect(throws: AstronomyError.earthNotAllowed) { try Positions.angleFromSun(of: .earth, at: outside) }
        #expect(throws: AstronomyError.earthNotAllowed) { try Positions.pairLongitude(.mars, .earth, at: outside) }
        #expect(throws: AstronomyError.earthNotAllowed) { try Positions.elongation(of: .earth, at: outside) }
        for body: CelestialBody in [.earthMoonBarycenter, .solarSystemBarycenter, .io] {
            #expect(throws: AstronomyError.invalidBody) { try Positions.illumination(of: body, at: Self.instant) }
        }
        #expect(throws: AstronomyError.invalidBody) { try Positions.elongation(of: .io, at: Self.instant) }
        #expect(throws: AstronomyError.badTime) { try Positions.illumination(of: .mars, at: outside) }
        #expect(throws: AstronomyError.badTime) { try Positions.elongation(of: .mars, at: .invalid) }
    }
}

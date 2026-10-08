//
//  EngineEquatorialTests.swift
//  AstronomyKit
//
//  Equatorial and horizontal coordinates: their composition, the errors,
//  the JPLValidationTests suites through the public path, and the Horizons
//  observer rows with their rates, ranges and range rates.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine equatorial and horizontal coordinates")
struct EngineEquatorialTests {
    typealias Positions = Engine.Positions

    static let bodies: [CelestialBody] = [
        .sun, .moon, .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
        .earthMoonBarycenter, .solarSystemBarycenter,
    ]

    static let time = Engine.Time(tt: 9_500.75, deltaTModel: .espenakMeeus)

    static func same(_ a: Engine.Equatorial, _ b: Engine.Equatorial) -> Bool {
        a.rightAscension.bitPattern == b.rightAscension.bitPattern
            && a.declination.bitPattern == b.declination.bitPattern && a.distance.bitPattern == b.distance.bitPattern
    }

    @Test("Equatorial coordinates are the geocentric position less the observer's, J2000 or of date")
    func composition() throws {
        for body in Self.bodies where body != .earth {
            for aberration in [Aberration.none, .corrected] {
                let geocentric = try Positions.geocentricPosition(of: body, at: Self.time, aberration: aberration)
                let fromCenter = try Positions.equatorial(
                    of: body, at: Self.time, from: .geocentric, equatorDate: .j2000, aberration: aberration)
                #expect(Self.same(fromCenter, try Engine.Equatorial(geocentric)), "\(body)")

                let site = Engine.Observers.vector(ashevilleObserver, at: Self.time)
                let topocentric = Engine.Vector<Engine.EQJ>(
                    x: geocentric.x - site.x, y: geocentric.y - site.y, z: geocentric.z - site.z, time: Self.time)
                let j2000 = try Positions.equatorial(
                    of: body, at: Self.time, from: ashevilleObserver, equatorDate: .j2000, aberration: aberration)
                #expect(Self.same(j2000, try Engine.Equatorial(topocentric)), "\(body)")
                let ofDate = try Positions.equatorial(
                    of: body, at: Self.time, from: ashevilleObserver, equatorDate: .ofDate, aberration: aberration)
                let rotated = Engine.FrameRotation.eqjToEqd(Self.time).apply(to: topocentric)
                #expect(Self.same(ofDate, try Engine.Equatorial(rotated)), "\(body)")
            }
        }
    }

    @Test("Horizontal coordinates are the apparent equatorial coordinates of date in the observer's sky")
    func horizontal() throws {
        for body in Self.bodies where body != .earth {
            let equatorial = try Positions.equatorial(
                of: body, at: Self.time, from: ashevilleObserver, equatorDate: .ofDate, aberration: .corrected)
            for refraction in [Refraction.none, .normal, .jplHorizons] {
                let horizontal = try Positions.horizontal(
                    of: body, at: Self.time, from: ashevilleObserver, refraction: refraction)
                let expected = Engine.Horizontal(
                    time: Self.time, observer: ashevilleObserver, rightAscension: equatorial.rightAscension,
                    declination: equatorial.declination, refraction: refraction)
                #expect(horizontal.azimuth.bitPattern == expected.azimuth.bitPattern, "\(body)")
                #expect(horizontal.altitude.bitPattern == expected.altitude.bitPattern, "\(body)")
                #expect(horizontal.rightAscension.bitPattern == expected.rightAscension.bitPattern, "\(body)")
                #expect(horizontal.declination.bitPattern == expected.declination.bitPattern, "\(body)")
            }
        }
    }

    @Test("Earth's center from itself has no direction; unsupported bodies and times throw")
    func errors() throws {
        for equatorDate in [EquatorDate.j2000, .ofDate] {
            #expect(throws: AstronomyError.badVector) {
                try Positions.equatorial(
                    of: .earth, at: Self.time, from: .geocentric, equatorDate: equatorDate, aberration: .corrected)
            }
            // From the surface, Earth's center is at the nadir.
            let nadir = try Positions.equatorial(
                of: .earth, at: Self.time, from: ashevilleObserver, equatorDate: equatorDate, aberration: .none)
            #expect(abs(nadir.distance * Engine.kilometersPerAU - 6_371) < 15)
            #expect(throws: AstronomyError.invalidBody) {
                try Positions.equatorial(
                    of: .io, at: Self.time, from: .geocentric, equatorDate: equatorDate, aberration: .corrected)
            }
            #expect(throws: AstronomyError.badTime) {
                try Positions.equatorial(
                    of: .mars, at: .invalid, from: .geocentric, equatorDate: equatorDate, aberration: .corrected)
            }
        }
        #expect(throws: AstronomyError.badTime) {
            try Positions.horizontal(of: .mars, at: .invalid, from: ashevilleObserver, refraction: .normal)
        }
    }

    // MARK: - Horizons azimuth and elevation

    static let horizontalRows = IndependentReferenceArchive.shared.horizontal

    /// The engine's azimuth and elevation for a Horizons row, without
    /// refraction for an airless row and with the `.jplHorizons` model for a
    /// refracted one, less the row's: the angle between the two directions
    /// and the elevation difference, in arcminutes.
    static func horizontalErrors(
        _ row: IndependentReferenceArchive.Horizontal, refraction: Refraction? = nil, days: Double = 0
    ) throws -> (angle: Double, elevation: Double) {
        let body = try PlutoSegmentSuites.EngineObserverRowTests.body(row.body)
        let ut = IndependentReferenceDate.universal(row.utc, deltaTModel: .espenakMeeus).universalTime
        let time = Engine.Time(ut: ut + days, deltaTModel: .espenakMeeus)
        let horizontal = try Positions.horizontal(
            of: body, at: time, from: ashevilleObserver,
            refraction: refraction ?? (row.refracted ? .jplHorizons : .none))
        let angle = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: horizontal.azimuth, decDegrees1: horizontal.altitude, raDegrees2: row.azimuthDegrees,
            decDegrees2: row.elevationDegrees)
        return (angle, abs(horizontal.altitude - row.elevationDegrees) * 60)
    }

    /// Horizons gives UTC, taken here as UT1, which it stays within 0.9 s
    /// of; the model's TT is then 5.9 s later than the published TT − UTC
    /// in 2026, which moves the Moon about 3″. Horizons' refraction is
    /// Sæmundsson's formula with the elevation held at −1° below that, the
    /// engine's `.jplHorizons` model. Measured, the largest angle is 5.6″,
    /// for the Moon, which the engine, like the public API, takes without
    /// aberration.
    @Test("Azimuth and elevation from Asheville against Horizons, with and without refraction")
    func horizonsHorizontal() throws {
        #expect(Self.horizontalRows.count == 96)
        for row in Self.horizontalRows {
            let errors = try Self.horizontalErrors(row)
            #expect(errors.angle <= row.angularToleranceArcminutes, "\(row.body) \(row.utc): \(errors.angle)′")
        }
    }

    @Test("The horizontal checks fail without refraction, with the normal model below the horizon, or a minute off")
    func horizontalNegativeControls() throws {
        let refracted = Self.horizontalRows.filter(\.refracted)
        let low = try #require(refracted.first { $0.elevationDegrees > 0 && $0.elevationDegrees < 10 })
        #expect(try Self.horizontalErrors(low, refraction: Refraction.none).elevation > 1)
        let below = try #require(refracted.first { $0.elevationDegrees < -10 })
        #expect(try Self.horizontalErrors(below, refraction: .normal).elevation > 1)
        let airless = try #require(Self.horizontalRows.first { !$0.refracted })
        #expect(try Self.horizontalErrors(airless, days: 1.0 / 1_440).angle > 1)
    }

    // MARK: - JPLValidationTests

    /// The geocentric and Asheville suites of `JPLValidationTests` through
    /// the call the public `equatorial(at:from:equatorDate:)` makes: J2000,
    /// with aberration, at each suite's tolerance.
    static let suites:
        [(body: CelestialBody, observer: Observer, references: [JPLReferencePoint], arcminutes: Double)] =
            [
                (.sun, .geocentric, SunValidationTests.referenceData, toleranceArcminutes),
                (.moon, .geocentric, MoonValidationTests.referenceData, toleranceArcminutes),
                (.mercury, .geocentric, MercuryValidationTests.referenceData, toleranceArcminutes),
                (.venus, .geocentric, VenusValidationTests.referenceData, toleranceArcminutes),
                (.mars, .geocentric, MarsValidationTests.referenceData, toleranceArcminutes),
                (.jupiter, .geocentric, JupiterValidationTests.referenceData, toleranceArcminutes),
                (.saturn, .geocentric, SaturnValidationTests.referenceData, toleranceArcminutes),
                (.uranus, .geocentric, UranusValidationTests.referenceData, toleranceArcminutes),
                (.neptune, .geocentric, NeptuneValidationTests.referenceData, toleranceArcminutes),
                (.pluto, .geocentric, PlutoValidationTests.referenceData, toleranceArcminutes),
                (.moon, ashevilleObserver, AshevilleValidationTests.moonData, toleranceArcminutes),
                (.mercury, ashevilleObserver, AshevilleValidationTests.mercuryData, toleranceArcminutes),
                (.venus, ashevilleObserver, AshevilleValidationTests.venusData, toleranceArcminutes),
                (.mars, ashevilleObserver, AshevilleValidationTests.marsData, toleranceArcminutes),
                (.jupiter, ashevilleObserver, AshevilleValidationTests.jupiterData, toleranceArcminutes),
                (.saturn, ashevilleObserver, AshevilleValidationTests.saturnData, toleranceArcminutes),
                (.uranus, ashevilleObserver, AshevilleValidationTests.uranusData, toleranceArcminutes),
                (.neptune, ashevilleObserver, AshevilleValidationTests.neptuneData, outerPlanetToleranceArcminutes),
                (.pluto, ashevilleObserver, AshevilleValidationTests.plutoData, outerPlanetToleranceArcminutes),
            ]

    @Test("The JPLValidationTests geocentric and Asheville suites at their tolerances")
    func jplValidation() throws {
        #expect(Self.suites.count == 19)
        for (body, observer, references, tolerance) in Self.suites {
            #expect(references.count == 4)
            for reference in references {
                let equatorial = try Positions.equatorial(
                    of: body, at: EnginePlanetHorizonsTests.time(reference), from: observer, equatorDate: .j2000,
                    aberration: .corrected)
                let arcminutes = angularSeparation(
                    ra1: reference.rightAscension, dec1: reference.declination, ra2: equatorial.rightAscension,
                    dec2: equatorial.declination)
                #expect(arcminutes <= tolerance, "\(body) \(reference.month)-\(reference.day): \(arcminutes)′")
            }
        }
    }
}

extension PlutoSegmentSuites {
    /// The Horizons observer rows of `reference-fixtures.json`: the Moon,
    /// Mars and Pluto at 1900, 2000 and 2100, and Mercury through its
    /// 2025-08-11 station. In `PlutoSegmentSuites` because Pluto's 1900 row
    /// is in the DE440 blend, which reads a segment of its integrated model.
    @Suite("Engine apparent positions against the Horizons observer rows")
    struct EngineObserverRowTests {
        typealias Positions = Engine.Positions

        static let rows = IndependentReferenceArchive.shared.observations

        static func body(_ name: String) throws -> CelestialBody {
            try #require(CelestialBody.allCases.first { $0.name.lowercased() == name })
        }

        static func time(_ row: IndependentReferenceArchive.Observation) -> Engine.Time {
            Engine.Time(ut: IndependentReferenceDate.civil(row.utc).universalTime, deltaTModel: .espenakMeeus)
        }

        /// Arcseconds per hour in a radian per day.
        static let arcsecondsPerHour = Engine.degreesPerRadian * 3_600 / 24

        /// The apparent right ascension rate times cos δ and the declination
        /// rate on the true equator of date, in arcseconds per hour, as
        /// Horizons' `dRA*cosD` and `d(DEC)/dt` define them.
        static func equatorialRates(_ state: Engine.State<Engine.EQJ>) -> (rightAscension: Double, declination: Double)
        {
            let s = Positions.trueEquatorState(state)
            let rho2 = s.x * s.x + s.y * s.y
            let rho = rho2.squareRoot()
            let r2 = rho2 + s.z * s.z
            let rightAscension = (s.x * s.vy - s.y * s.vx) / rho2 * (rho / r2.squareRoot())
            let declination = (rho * s.vz - s.z * (s.x * s.vx + s.y * s.vy) / rho) / r2
            return (rightAscension * arcsecondsPerHour, declination * arcsecondsPerHour)
        }

        /// The rates' allowance in arcseconds per hour. The planets' rates
        /// are within 0.013″ per hour of Horizons'; 0.02 is that measured
        /// bound rounded up, not a published accuracy. The Moon gets neither
        /// light time nor aberration, as in the public API and the C engine,
        /// while Horizons' apparent rates include aberration. Its shift, up
        /// to κ = 20.49552″, turns with the Moon's motion of up to 0.26 radian
        /// a day relative to Earth's velocity, so its rate reaches 0.22″ per
        /// hour; the Moon is allowed 0.25 (measured 0.14).
        static func rateAllowance(_ body: CelestialBody) -> Double { body == .moon ? 0.25 : 0.02 }

        /// The apparent rates of `body` at `time` less the row's, in
        /// arcseconds per hour.
        static func rateErrors(
            _ body: CelestialBody, at time: Engine.Time, _ row: IndependentReferenceArchive.Observation
        ) throws -> (rightAscension: Double, declination: Double) {
            let rates = equatorialRates(try Positions.geocentricState(of: body, at: time, aberration: .corrected))
            return (
                abs(rates.rightAscension - row.rightAscensionRateArcsecondsPerHour),
                abs(rates.declination - row.declinationRateArcsecondsPerHour)
            )
        }

        /// The allowance for each body's geocentric range in
        /// `distance-fixtures.json`, as `DistanceAccuracyTests` applies it.
        static func rangeAllowanceKm(_ body: CelestialBody) throws -> Double {
            try #require(
                DistanceReferenceArchive.shared.references.first { $0.body == body.name && $0.mode == "geocentric" }
            ).allowedErrorKm
        }

        /// Horizons' columns, as its observer tables define them: the
        /// astrometric ICRF direction; the apparent ecliptic of date; the
        /// apparent RA and Dec rates on the true equator of date; `delta`, the
        /// range at the time light left the target; and `deldot`, the
        /// target's velocity then less the observer's now, along the line of
        /// sight. `backdatedPosition` with no aberration gives `delta` for
        /// every body, the Moon included, whose geocentric position has no
        /// light time: without it the Moon's range is off by Earth's orbital
        /// motion over the light time, 36 km in 2000. The engine solves light
        /// time in the heliocentric frame and Horizons in the barycentric one,
        /// which differ by the Sun's motion over the light time, about 13 m/s.
        @Test("Positions, rates, ranges and range rates against the Horizons observer rows")
        func observerRows() throws {
            #expect(Self.rows.count == 12)
            for row in Self.rows {
                let body = try Self.body(row.body)
                let time = Self.time(row)
                let tolerance = row.angularToleranceArcminutes
                let label = "\(row.body) \(row.utc)"

                let astrometric = try Positions.equatorial(
                    of: body, at: time, from: .geocentric, equatorDate: .j2000, aberration: .none)
                let arcminutes = IndependentReferenceMath.angularSeparationArcminutes(
                    raDegrees1: astrometric.rightAscension * 15, decDegrees1: astrometric.declination,
                    raDegrees2: row.rightAscensionDegrees, decDegrees2: row.declinationDegrees)
                #expect(arcminutes <= tolerance, "\(label): \(arcminutes)′")

                let ecliptic = try Positions.geocentricEclipticState(of: body, at: time, aberration: .corrected)
                let longitude = IndependentReferenceMath.wrappedDifference(
                    ecliptic.longitude, row.eclipticLongitudeDegrees)
                #expect(abs(longitude) * 60 <= tolerance, "\(label)")
                #expect(abs(ecliptic.latitude - row.eclipticLatitudeDegrees) * 60 <= tolerance, "\(label)")

                let rates = try Self.rateErrors(body, at: time, row)
                #expect(rates.rightAscension <= Self.rateAllowance(body), "\(label): \(rates.rightAscension)″/h")
                #expect(rates.declination <= Self.rateAllowance(body), "\(label): \(rates.declination)″/h")

                let backdated = try Positions.backdatedPosition(of: body, seenFrom: .earth, at: time, aberration: .none)
                let rangeKm = abs(backdated.length - row.apparentRangeAU) * Engine.kilometersPerAU
                #expect(rangeKm <= (try Self.rangeAllowanceKm(body)), "\(label): \(rangeKm) km")

                let direction = SIMD3(backdated.x, backdated.y, backdated.z) / backdated.length
                let target = try Positions.heliocentricState(of: body, at: backdated.time).velocityVector
                let earth = try Positions.heliocentricState(of: .earth, at: time).velocityVector
                let rangeRate = (direction * (target - earth)).sum() * Engine.kilometersPerAU / Engine.secondsPerDay
                // Measured: 9.0e-5 km/s at most (Pluto, 1900, in the DE440 blend), 7e-6 elsewhere.
                #expect(abs(rangeRate - row.rangeRateKmPerSecond) <= 1e-4, "\(label): \(rangeRate) km/s")
            }
        }

        @Test("The rate checks fail a day off")
        func rateNegativeControls() throws {
            for name in ["moon", "mars"] {
                let row = try #require(Self.rows.first { $0.body == name })
                let body = try Self.body(name)
                let errors = try Self.rateErrors(body, at: Self.time(row).adding(days: 1), row)
                #expect(max(errors.rightAscension, errors.declination) > Self.rateAllowance(body), "\(name)")
            }
        }
    }
}

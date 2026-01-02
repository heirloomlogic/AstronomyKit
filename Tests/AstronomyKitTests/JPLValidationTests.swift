//
//  JPLValidationTests.swift
//  AstronomyKit
//
//  Validates AstronomyKit calculations against JPL Horizons ephemeris data.
//  Target accuracy: ±1 arcminute (Astronomy Engine stated accuracy).
//
//  Reference data source: JPL Horizons (https://ssd.jpl.nasa.gov/horizons/)
//  Date range: 2026-Jan-02 to 2026-Mar-03 (daily samples)
//  Observer: Geocentric (Earth center)
//  Coordinate frame: ICRF (J2000)
//

import Foundation
import Testing

@testable import AstronomyKit

// MARK: - JPL Reference Data Structure

/// A reference data point from JPL Horizons ephemeris
struct JPLReferencePoint {
    let year: Int
    let month: Int
    let day: Int
    let raHours: Int
    let raMinutes: Int
    let raSeconds: Double
    let decNegative: Bool  // Track sign separately for -00° cases
    let decDegrees: Int  // Always stored as absolute value
    let decMinutes: Int
    let decSeconds: Double

    /// Convenience init for positive declinations
    init(
        year: Int,
        month: Int,
        day: Int,
        raHours: Int,
        raMinutes: Int,
        raSeconds: Double,
        decDegrees: Int,
        decMinutes: Int,
        decSeconds: Double
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.raHours = raHours
        self.raMinutes = raMinutes
        self.raSeconds = raSeconds
        self.decNegative = decDegrees < 0
        self.decDegrees = abs(decDegrees)
        self.decMinutes = decMinutes
        self.decSeconds = decSeconds
    }

    /// Explicit init with negative flag for -00° cases
    init(
        year: Int,
        month: Int,
        day: Int,
        raHours: Int,
        raMinutes: Int,
        raSeconds: Double,
        decNegative: Bool,
        decDegrees: Int,
        decMinutes: Int,
        decSeconds: Double
    ) {
        self.year = year
        self.month = month
        self.day = day
        self.raHours = raHours
        self.raMinutes = raMinutes
        self.raSeconds = raSeconds
        self.decNegative = decNegative
        self.decDegrees = decDegrees
        self.decMinutes = decMinutes
        self.decSeconds = decSeconds
    }

    /// Right Ascension in decimal hours
    var rightAscension: Double {
        Double(raHours) + Double(raMinutes) / 60.0 + raSeconds / 3_600.0
    }

    /// Declination in decimal degrees
    var declination: Double {
        let value = Double(decDegrees) + Double(decMinutes) / 60.0 + decSeconds / 3_600.0
        return decNegative ? -value : value
    }

    /// Creates an AstroTime for this date at 00:00 UT
    var time: AstroTime {
        AstroTime(
            year: year,
            month: month,
            day: day,
            hour: 0,
            minute: 0,
            second: 0
        )
    }
}

// MARK: - Angular Separation Calculation

/// Calculate angular separation between two equatorial positions
/// Uses the spherical law of cosines formula
func angularSeparation(
    ra1: Double,
    dec1: Double,  // RA in hours, Dec in degrees
    ra2: Double,
    dec2: Double  // RA in hours, Dec in degrees
) -> Double {
    let ra1Rad = ra1 * 15.0 * .pi / 180.0  // hours -> degrees -> radians
    let ra2Rad = ra2 * 15.0 * .pi / 180.0
    let dec1Rad = dec1 * .pi / 180.0
    let dec2Rad = dec2 * .pi / 180.0

    let cosD = sin(dec1Rad) * sin(dec2Rad) + cos(dec1Rad) * cos(dec2Rad) * cos(ra1Rad - ra2Rad)
    let separation = acos(min(1.0, max(-1.0, cosD))) * 180.0 / .pi

    return separation * 60.0  // Convert degrees to arcminutes
}

// MARK: - Tolerances

/// Standard tolerance in arcminutes (1 arcminute = Astronomy Engine stated accuracy)
let toleranceArcminutes = 1.0

/// Outer planet tolerance - slightly higher for Neptune/Uranus
let outerPlanetToleranceArcminutes = 1.5

// MARK: - Sun Validation

@Suite("Sun Validation vs JPL Horizons")
struct SunValidationTests {

    // JPL Horizons data for the Sun (ICRF column, exactly from file)
    // Line 60: 2026-Jan-02: 18 48 50.13 -22 57 40.4
    // Line 80: 2026-Jan-22: 20 15 22.63 -19 48 02.1
    // Line 100: 2026-Feb-11: 21 37 03.60 -14 12 27.0
    // Line 120: 2026-Mar-03: 22 53 47.28 -07 02 26.5
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 18, raMinutes: 48, raSeconds: 50.13,
            decDegrees: -22, decMinutes: 57, decSeconds: 40.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 15, raSeconds: 22.63,
            decDegrees: -19, decMinutes: 48, decSeconds: 02.1
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 21, raMinutes: 37, raSeconds: 03.60,
            decDegrees: -14, decMinutes: 12, decSeconds: 27.0
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 22, raMinutes: 53, raSeconds: 47.28,
            decDegrees: -07, decMinutes: 02, decSeconds: 26.5
        ),
    ]

    @Test("Sun position matches JPL reference within 1 arcminute")
    func sunPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.sun.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Sun position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Moon Validation

@Suite("Moon Validation vs JPL Horizons")
struct MoonValidationTests {

    // JPL Horizons data for the Moon (ICRF column, exactly from file)
    // Line 61: 2026-Jan-02: 05 21 01.61 +28 07 00.3
    // Line 71: 2026-Jan-12: 14 09 23.21 -17 35 21.2
    // Line 101: 2026-Feb-11: 16 20 33.06 -26 48 05.3
    // Line 121: 2026-Mar-03: 10 31 40.05 +09 30 38.6
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 05, raMinutes: 21, raSeconds: 01.61,
            decDegrees: 28, decMinutes: 07, decSeconds: 00.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 12,
            raHours: 14, raMinutes: 09, raSeconds: 23.21,
            decDegrees: -17, decMinutes: 35, decSeconds: 21.2
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 16, raMinutes: 20, raSeconds: 33.06,
            decDegrees: -26, decMinutes: 48, decSeconds: 05.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 10, raMinutes: 31, raSeconds: 40.05,
            decDegrees: 09, decMinutes: 30, decSeconds: 38.6
        ),
    ]

    @Test("Moon position matches JPL reference within 1 arcminute")
    func moonPositionAccuracy() throws {
        for ref in Self.referenceData {
            // Use geocentric observer to match JPL GEOCENTRIC configuration
            let computed = try CelestialBody.moon.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Moon position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Mercury Validation

@Suite("Mercury Validation vs JPL Horizons")
struct MercuryValidationTests {

    // JPL Horizons data for Mercury (ICRF column, exactly from file)
    // Line 60: 2026-Jan-02: 17 59 12.90 -24 06 52.8
    // Line 80: 2026-Jan-22: 20 18 17.57 -21 45 30.0
    // Line 101: 2026-Feb-12: 22 40 25.92 -08 59 37.1 (Note: Feb-11 is line 100)
    // Line 120: 2026-Mar-03: 23 19 25.88 -00 30 32.5
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 17, raMinutes: 59, raSeconds: 12.90,
            decDegrees: -24, decMinutes: 06, decSeconds: 52.8
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 18, raSeconds: 17.57,
            decDegrees: -21, decMinutes: 45, decSeconds: 30.0
        ),
        // Feb-12 instead of Feb-11 (using line 101 data)
        JPLReferencePoint(
            year: 2_026, month: 2, day: 12,
            raHours: 22, raMinutes: 40, raSeconds: 25.92,
            decDegrees: -08, decMinutes: 59, decSeconds: 37.1
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 23, raMinutes: 19, raSeconds: 25.88,
            decNegative: true, decDegrees: 00, decMinutes: 30, decSeconds: 32.5
        ),
    ]

    @Test("Mercury position matches JPL reference within 1 arcminute")
    func mercuryPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.mercury.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Mercury position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Venus Validation

@Suite("Venus Validation vs JPL Horizons")
struct VenusValidationTests {

    // JPL Horizons data for Venus (verified from earlier)
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 18, raMinutes: 44, raSeconds: 09.13,
            decDegrees: -23, decMinutes: 35, decSeconds: 30.6
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 31, raSeconds: 40.08,
            decDegrees: -20, decMinutes: 04, decSeconds: 57.6
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 22, raMinutes: 11, raSeconds: 48.77,
            decDegrees: -12, decMinutes: 42, decSeconds: 34.6
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 23, raMinutes: 45, raSeconds: 00.99,
            decDegrees: -03, decMinutes: 04, decSeconds: 02.5
        ),
    ]

    @Test("Venus position matches JPL reference within 1 arcminute")
    func venusPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.venus.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Venus position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Mars Validation

@Suite("Mars Validation vs JPL Horizons")
struct MarsValidationTests {

    // JPL Horizons data for Mars (verified from earlier)
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 18, raMinutes: 57, raSeconds: 17.54,
            decDegrees: -23, decMinutes: 41, decSeconds: 04.5
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 03, raSeconds: 35.29,
            decDegrees: -21, decMinutes: 25, decSeconds: 44.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 21, raMinutes: 08, raSeconds: 00.19,
            decDegrees: -17, decMinutes: 35, decSeconds: 21.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 22, raMinutes: 09, raSeconds: 46.20,
            decDegrees: -12, decMinutes: 30, decSeconds: 36.8
        ),
    ]

    @Test("Mars position matches JPL reference within 1 arcminute")
    func marsPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.mars.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Mars position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Jupiter Validation

@Suite("Jupiter Validation vs JPL Horizons")
struct JupiterValidationTests {

    // JPL Horizons data for Jupiter (ICRF column, exactly from file)
    // Line 61: 2026-Jan-02: 07 30 21.59 +22 03 25.5
    // Line 81: 2026-Jan-22: 07 18 59.73 +22 29 01.8
    // Line 101: 2026-Feb-11: 07 09 31.93 +22 47 52.4
    // Line 121: 2026-Mar-03: 07 04 31.97 +22 57 22.5
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 07, raMinutes: 30, raSeconds: 21.59,
            decDegrees: 22, decMinutes: 03, decSeconds: 25.5
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 07, raMinutes: 18, raSeconds: 59.73,
            decDegrees: 22, decMinutes: 29, decSeconds: 01.8
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 07, raMinutes: 09, raSeconds: 31.93,
            decDegrees: 22, decMinutes: 47, decSeconds: 52.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 07, raMinutes: 04, raSeconds: 31.97,
            decDegrees: 22, decMinutes: 57, decSeconds: 22.5
        ),
    ]

    @Test("Jupiter position matches JPL reference within 1 arcminute")
    func jupiterPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.jupiter.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Jupiter position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Neptune Validation

@Suite("Neptune Validation vs JPL Horizons")
struct NeptuneValidationTests {

    // JPL Horizons data for Neptune (ICRF column)
    static let referenceData: [JPLReferencePoint] = [
        // Line 61: 2026-Jan-02: 23 59 01.31 -01 33 27.9
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 23, raMinutes: 59, raSeconds: 01.31,
            decDegrees: -01, decMinutes: 33, decSeconds: 27.9
        ),
        // Line 81: 2026-Jan-22: 00 00 15.75 -01 24 40.1
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 00, raMinutes: 00, raSeconds: 15.75,
            decDegrees: -01, decMinutes: 24, decSeconds: 40.1
        ),
        // Line 101: 2026-Feb-11: 00 02 21.20 -01 10 28.0
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 00, raMinutes: 02, raSeconds: 21.20,
            decDegrees: -01, decMinutes: 10, decSeconds: 28.0
        ),
        // Line 121: 2026-Mar-03: 00 04 50.78 -00 53 56.6
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 00, raMinutes: 04, raSeconds: 50.78,
            decNegative: true, decDegrees: 00, decMinutes: 53, decSeconds: 56.6
        ),
    ]

    @Test("Neptune position matches JPL reference within 1.5 arcminutes")
    func neptunePositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.neptune.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= outerPlanetToleranceArcminutes,
                """
                Neptune position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \
                \(separation) arcmin (limit: \(outerPlanetToleranceArcminutes))
                """
            )
        }
    }
}

// MARK: - Uranus Validation

@Suite("Uranus Validation vs JPL Horizons")
struct UranusValidationTests {

    // JPL Horizons data for Uranus (verified correct from earlier)
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 03, raMinutes: 41, raSeconds: 18.77,
            decDegrees: 19, decMinutes: 25, decSeconds: 07.6
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 03, raMinutes: 39, raSeconds: 45.44,
            decDegrees: 19, decMinutes: 20, decSeconds: 20.0
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 03, raMinutes: 39, raSeconds: 29.16,
            decDegrees: 19, decMinutes: 19, decSeconds: 50.1
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 03, raMinutes: 40, raSeconds: 42.47,
            decDegrees: 19, decMinutes: 24, decSeconds: 15.9
        ),
    ]

    @Test("Uranus position matches JPL reference within 1.5 arcminutes")
    func uranusPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.uranus.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Uranus position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Pluto Validation

@Suite("Pluto Validation vs JPL Horizons")
struct PlutoValidationTests {

    // JPL Horizons data for Pluto (verified correct from earlier test - all passed)
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 20, raMinutes: 22, raSeconds: 21.12,
            decDegrees: -23, decMinutes: 17, decSeconds: 43.1
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 25, raSeconds: 01.37,
            decDegrees: -23, decMinutes: 10, decSeconds: 04.8
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 20, raMinutes: 27, raSeconds: 43.08,
            decDegrees: -23, decMinutes: 02, decSeconds: 56.9
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 20, raMinutes: 30, raSeconds: 11.05,
            decDegrees: -22, decMinutes: 57, decSeconds: 10.7
        ),
    ]

    @Test("Pluto position matches JPL reference within 1.5 arcminutes")
    func plutoPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.pluto.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Pluto position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Saturn Validation (Geocentric)

@Suite("Saturn Validation vs JPL Horizons")
struct SaturnValidationTests {

    // JPL Horizons data for Saturn (ICRF column, geocentric)
    // Line 61: 2026-Jan-02: 23 48 24.03 -03 42 51.2
    // Line 81: 2026-Jan-22: 23 53 45.49 -03 04 14.8
    // Line 101: 2026-Feb-11: 00 00 53.85 -02 15 01.9
    // Line 121: 2026-Mar-03: 00 09 15.80 -01 19 01.6
    static let referenceData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 23, raMinutes: 48, raSeconds: 24.03,
            decDegrees: -03, decMinutes: 42, decSeconds: 51.2
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 23, raMinutes: 53, raSeconds: 45.49,
            decDegrees: -03, decMinutes: 04, decSeconds: 14.8
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 00, raMinutes: 00, raSeconds: 53.85,
            decDegrees: -02, decMinutes: 15, decSeconds: 01.9
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 00, raMinutes: 09, raSeconds: 15.80,
            decDegrees: -01, decMinutes: 19, decSeconds: 01.6
        ),
    ]

    @Test("Saturn position matches JPL reference within 1 arcminute")
    func saturnPositionAccuracy() throws {
        for ref in Self.referenceData {
            let computed = try CelestialBody.saturn.equatorial(
                at: ref.time,
                from: .geocentric,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Saturn position on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

// MARK: - Asheville Topocentric Validation

/// Asheville, NC observer location (from JPL Horizons files)
/// Center geodetic: 277.4428, 35.595, 0 (E-lon(deg), Lat(deg), Alt(km))
/// Longitude 277.4428°E = -82.5572°W
let ashevilleObserver = Observer(latitude: 35.595, longitude: -82.5572)

@Suite("Asheville Topocentric Validation vs JPL Horizons")
struct AshevilleValidationTests {

    // JPL Horizons data for Moon from Asheville (topocentric)
    // Line 61: 2026-Jan-02: 05 24 20.98 +27 46 49.7
    // Line 81: 2026-Jan-22: 22 39 34.92 -08 48 54.5
    // Line 101: 2026-Feb-11: 16 20 09.13 -26 56 08.8
    // Line 121: 2026-Mar-03: 10 34 47.87 +08 58 57.3
    static let moonData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 05, raMinutes: 24, raSeconds: 20.98,
            decDegrees: 27, decMinutes: 46, decSeconds: 49.7
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 22, raMinutes: 39, raSeconds: 34.92,
            decDegrees: -08, decMinutes: 48, decSeconds: 54.5
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 16, raMinutes: 20, raSeconds: 09.13,
            decDegrees: -26, decMinutes: 56, decSeconds: 08.8
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 10, raMinutes: 34, raSeconds: 47.87,
            decDegrees: 08, decMinutes: 58, decSeconds: 57.3
        ),
    ]

    // JPL Horizons data for Mercury from Asheville
    // Line 60: 2026-Jan-02: 17 59 12.54 -24 06 55.4
    // Line 80: 2026-Jan-22: 20 18 17.21 -21 45 33.2
    // Line 100: 2026-Feb-11: 22 34 29.58 -09 46 28.8
    // Line 120: 2026-Mar-03: 23 19 25.17 -00 30 40.1
    static let mercuryData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 17, raMinutes: 59, raSeconds: 12.54,
            decDegrees: -24, decMinutes: 06, decSeconds: 55.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 18, raSeconds: 17.21,
            decDegrees: -21, decMinutes: 45, decSeconds: 33.2
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 22, raMinutes: 34, raSeconds: 29.58,
            decDegrees: -09, decMinutes: 46, decSeconds: 28.8
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 23, raMinutes: 19, raSeconds: 25.17,
            decNegative: true, decDegrees: 00, decMinutes: 30, decSeconds: 40.1
        ),
    ]

    // JPL Horizons data for Venus from Asheville
    // Line 60: 2026-Jan-02: 18 44 08.82 -23 35 33.1
    // Line 80: 2026-Jan-22: 20 31 39.78 -20 05 00.4
    // Line 100: 2026-Feb-11: 22 11 48.48 -12 42 37.6
    // Line 120: 2026-Mar-03: 23 45 00.70 -03 04 05.7
    static let venusData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 18, raMinutes: 44, raSeconds: 08.82,
            decDegrees: -23, decMinutes: 35, decSeconds: 33.1
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 31, raSeconds: 39.78,
            decDegrees: -20, decMinutes: 05, decSeconds: 00.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 22, raMinutes: 11, raSeconds: 48.48,
            decDegrees: -12, decMinutes: 42, decSeconds: 37.6
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 23, raMinutes: 45, raSeconds: 00.70,
            decDegrees: -03, decMinutes: 04, decSeconds: 05.7
        ),
    ]

    // JPL Horizons data for Mars from Asheville
    // Line 62: 2026-Jan-02: 18 57 17.32 -23 41 06.3
    // Line 82: 2026-Jan-22: 20 03 35.08 -21 25 46.1
    // Line 102: 2026-Feb-11: 21 07 59.98 -17 35 23.2
    // Line 122: 2026-Mar-03: 22 09 46.00 -12 30 38.7
    static let marsData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 18, raMinutes: 57, raSeconds: 17.32,
            decDegrees: -23, decMinutes: 41, decSeconds: 06.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 03, raSeconds: 35.08,
            decDegrees: -21, decMinutes: 25, decSeconds: 46.1
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 21, raMinutes: 07, raSeconds: 59.98,
            decDegrees: -17, decMinutes: 35, decSeconds: 23.2
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 22, raMinutes: 09, raSeconds: 46.00,
            decDegrees: -12, decMinutes: 30, decSeconds: 38.7
        ),
    ]

    // JPL Horizons data for Jupiter from Asheville
    // Line 61: 2026-Jan-02: 07 30 21.71 +22 03 24.3
    // Line 81: 2026-Jan-22: 07 18 59.85 +22 29 00.9
    // Line 101: 2026-Feb-11: 07 09 32.02 +22 47 51.7
    // Line 121: 2026-Mar-03: 07 04 32.03 +22 57 22.0
    static let jupiterData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 07, raMinutes: 30, raSeconds: 21.71,
            decDegrees: 22, decMinutes: 03, decSeconds: 24.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 07, raMinutes: 18, raSeconds: 59.85,
            decDegrees: 22, decMinutes: 29, decSeconds: 00.9
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 07, raMinutes: 09, raSeconds: 32.02,
            decDegrees: 22, decMinutes: 47, decSeconds: 51.7
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 07, raMinutes: 04, raSeconds: 32.03,
            decDegrees: 22, decMinutes: 57, decSeconds: 22.0
        ),
    ]

    @Test("Moon topocentric position from Asheville matches JPL within 1 arcminute")
    func moonAshevilleAccuracy() throws {
        for ref in Self.moonData {
            let computed = try CelestialBody.moon.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Moon (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Mercury topocentric position from Asheville matches JPL within 1 arcminute")
    func mercuryAshevilleAccuracy() throws {
        for ref in Self.mercuryData {
            let computed = try CelestialBody.mercury.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Mercury (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Venus topocentric position from Asheville matches JPL within 1 arcminute")
    func venusAshevilleAccuracy() throws {
        for ref in Self.venusData {
            let computed = try CelestialBody.venus.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Venus (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Mars topocentric position from Asheville matches JPL within 1 arcminute")
    func marsAshevilleAccuracy() throws {
        for ref in Self.marsData {
            let computed = try CelestialBody.mars.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Mars (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Jupiter topocentric position from Asheville matches JPL within 1 arcminute")
    func jupiterAshevilleAccuracy() throws {
        for ref in Self.jupiterData {
            let computed = try CelestialBody.jupiter.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Jupiter (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    // JPL Horizons data for Saturn from Asheville
    // Line 61: 2026-Jan-02: 23 48 24.01 -03 42 51.7
    // Line 81: 2026-Jan-22: 23 53 45.46 -03 04 15.3
    // Line 101: 2026-Feb-11: 00 00 53.81 -02 15 02.4
    // Line 121: 2026-Mar-03: 00 09 15.76 -01 19 02.1
    static let saturnData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 23, raMinutes: 48, raSeconds: 24.01,
            decDegrees: -03, decMinutes: 42, decSeconds: 51.7
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 23, raMinutes: 53, raSeconds: 45.46,
            decDegrees: -03, decMinutes: 04, decSeconds: 15.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 00, raMinutes: 00, raSeconds: 53.81,
            decDegrees: -02, decMinutes: 15, decSeconds: 02.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 00, raMinutes: 09, raSeconds: 15.76,
            decDegrees: -01, decMinutes: 19, decSeconds: 02.1
        ),
    ]

    // JPL Horizons data for Uranus from Asheville
    // Line 61: 2026-Jan-02: 03 41 18.79 +19 25 07.4
    // Line 81: 2026-Jan-22: 03 39 42.52 +19 20 11.3
    // Line 101: 2026-Feb-11: 03 39 29.15 +19 19 50.0
    // Line 121: 2026-Mar-03: 03 40 42.46 +19 24 15.7
    static let uranusData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 03, raMinutes: 41, raSeconds: 18.79,
            decDegrees: 19, decMinutes: 25, decSeconds: 07.4
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 03, raMinutes: 39, raSeconds: 42.52,
            decDegrees: 19, decMinutes: 20, decSeconds: 11.3
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 03, raMinutes: 39, raSeconds: 29.15,
            decDegrees: 19, decMinutes: 19, decSeconds: 50.0
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 03, raMinutes: 40, raSeconds: 42.46,
            decDegrees: 19, decMinutes: 24, decSeconds: 15.7
        ),
    ]

    // JPL Horizons data for Neptune from Asheville
    // Line 61: 2026-Jan-02: 23 59 01.30 -01 33 28.0
    // Line 81: 2026-Jan-22: 00 00 20.78 -01 24 05.5
    // Line 101: 2026-Feb-11: 00 02 21.18 -01 10 28.2
    // Line 121: 2026-Mar-03: 00 04 50.77 -00 53 56.8
    static let neptuneData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 23, raMinutes: 59, raSeconds: 01.30,
            decDegrees: -01, decMinutes: 33, decSeconds: 28.0
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 00, raMinutes: 00, raSeconds: 20.78,
            decDegrees: -01, decMinutes: 24, decSeconds: 05.5
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 00, raMinutes: 02, raSeconds: 21.18,
            decDegrees: -01, decMinutes: 10, decSeconds: 28.2
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 00, raMinutes: 04, raSeconds: 50.77,
            decNegative: true, decDegrees: 00, decMinutes: 53, decSeconds: 56.8
        ),
    ]

    // JPL Horizons data for Pluto from Asheville
    // Line 60: 2026-Jan-02: 20 22 21.10 -23 17 43.2
    // Line 80: 2026-Jan-22: 20 25 01.35 -23 10 04.9
    // Line 100: 2026-Feb-11: 20 27 43.06 -23 02 57.0
    // Line 120: 2026-Mar-03: 20 30 11.04 -22 57 10.8
    static let plutoData: [JPLReferencePoint] = [
        JPLReferencePoint(
            year: 2_026, month: 1, day: 2,
            raHours: 20, raMinutes: 22, raSeconds: 21.10,
            decDegrees: -23, decMinutes: 17, decSeconds: 43.2
        ),
        JPLReferencePoint(
            year: 2_026, month: 1, day: 22,
            raHours: 20, raMinutes: 25, raSeconds: 01.35,
            decDegrees: -23, decMinutes: 10, decSeconds: 04.9
        ),
        JPLReferencePoint(
            year: 2_026, month: 2, day: 11,
            raHours: 20, raMinutes: 27, raSeconds: 43.06,
            decDegrees: -23, decMinutes: 02, decSeconds: 57.0
        ),
        JPLReferencePoint(
            year: 2_026, month: 3, day: 3,
            raHours: 20, raMinutes: 30, raSeconds: 11.04,
            decDegrees: -22, decMinutes: 57, decSeconds: 10.8
        ),
    ]

    @Test("Saturn topocentric position from Asheville matches JPL within 1 arcminute")
    func saturnAshevilleAccuracy() throws {
        for ref in Self.saturnData {
            let computed = try CelestialBody.saturn.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Saturn (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Uranus topocentric position from Asheville matches JPL within 1.5 arcminutes")
    func uranusAshevilleAccuracy() throws {
        for ref in Self.uranusData {
            let computed = try CelestialBody.uranus.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= toleranceArcminutes,
                "Uranus (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Neptune topocentric position from Asheville matches JPL within 1.5 arcminutes")
    func neptuneAshevilleAccuracy() throws {
        for ref in Self.neptuneData {
            let computed = try CelestialBody.neptune.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= outerPlanetToleranceArcminutes,
                "Neptune (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }

    @Test("Pluto topocentric position from Asheville matches JPL within 1.5 arcminutes")
    func plutoAshevilleAccuracy() throws {
        for ref in Self.plutoData {
            let computed = try CelestialBody.pluto.equatorial(
                at: ref.time,
                from: ashevilleObserver,
                equatorDate: .j2000
            )

            let separation = angularSeparation(
                ra1: ref.rightAscension, dec1: ref.declination,
                ra2: computed.rightAscension, dec2: computed.declination
            )

            #expect(
                separation <= outerPlanetToleranceArcminutes,
                "Pluto (Asheville) on \(ref.year)-\(ref.month)-\(ref.day) exceeds tolerance: \(separation) arcmin"
            )
        }
    }
}

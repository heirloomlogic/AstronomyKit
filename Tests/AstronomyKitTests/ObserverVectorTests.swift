//
//  ObserverVectorTests.swift
//  AstronomyKit
//
//  Tests for Observer vector/state functionality.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Observer Vector Tests")
struct ObserverVectorTests {
    let greenwich = Observer.greenwich

    @Test("Observer vector returns position")
    func observerVector() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let vector = try greenwich.vector(at: time)

        // Observer on Earth should have position magnitude ~Earth radius in AU
        // Earth radius ~4.26e-5 AU
        #expect(vector.magnitude > 0)
        #expect(vector.magnitude < 0.001)  // Much less than 1 AU
    }

    @Test("Observer state returns position and velocity")
    func observerState() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let state = try greenwich.state(at: time)

        #expect(state.position.magnitude > 0)
        #expect(state.velocity.magnitude > 0)
    }

    @Test("J2000 vs of-date coordinates differ")
    func j2000VsOfDate() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)

        let j2000 = try greenwich.vector(at: time, equator: .j2000)
        let ofDate = try greenwich.vector(at: time, equator: .ofDate)

        // Due to precession, these should be slightly different
        // (but very close since we're near J2000)
        let diff = abs(j2000.x - ofDate.x) + abs(j2000.y - ofDate.y) + abs(j2000.z - ofDate.z)
        #expect(diff > 0)  // They should differ
        #expect(diff < 0.001)  // But not by much
    }

    @Test("Observer at equator vs pole")
    func equatorVsPole() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)

        let equator = Observer(latitude: 0, longitude: 0)
        let pole = Observer(latitude: 90, longitude: 0)

        let eqVec = try equator.vector(at: time)
        let poleVec = try pole.vector(at: time)

        // Equator position should have larger x/y components
        // Pole position should have larger z component
        // (This depends on Earth's orientation at the time)
        #expect(eqVec.magnitude > 0)
        #expect(poleVec.magnitude > 0)
    }

    // MARK: - Absolute Geometry

    /// Checks observer vectors against the engine's documented ellipsoid and
    /// the Earth rotation angle, not against the inverse transform.
    @Suite("Absolute Geometry")
    struct AbsoluteGeometryTests {
        /// IERS Conventions (2010) Table 1.1: equatorial radius 6,378,136.6 m
        /// and flattening 1/298.25642, the ellipsoid declared in astronomy.h.
        static let equatorialRadiusKm = 6_378.1366
        static let polarRadiusKm = equatorialRadiusKm * (1 - 1 / 298.25642)

        /// The DE405 astronomical unit, 149,597,870.691 km (Standish 1998, JPL
        /// IOM 312.F-98-048), which the engine's `KM_PER_AU` encodes.
        static let kilometersPerAU = 149_597_870.691

        /// 1 mm. Rounding at Earth-radius scale is about 1e-12 km, and the
        /// engine's AU literal is within 1e-5 km of the DE405 value, which
        /// scales an Earth radius by 5e-10 km. Swapping in the WGS 84
        /// flattening moves the polar radius by 5.8 cm.
        static let toleranceKm = 1e-6

        static let heightMeters = 1_000.0
        static let time = AstroTime(year: 2_025, month: 6, day: 21)

        @Test("An equatorial observer is the equatorial radius plus height from the geocenter")
        func equatorialRadius() throws {
            let observer = Observer(latitude: 0, longitude: 0, height: Self.heightMeters)
            let expected = Self.equatorialRadiusKm + Self.heightMeters / 1_000

            for equator in [EquatorDate.ofDate, .j2000] {
                let radius = try observer.vector(at: Self.time, equator: equator).magnitude * Self.kilometersPerAU
                #expect(abs(radius - expected) < Self.toleranceKm, "\(equator): \(radius) km, expected \(expected) km")
            }

            #expect(try observer.vector(at: Self.time, equator: .ofDate).z == 0)
        }

        @Test("A polar observer is on the rotation axis at the polar radius plus height", arguments: [90.0, -90.0])
        func polarRadius(latitude: Double) throws {
            let observer = Observer(latitude: latitude, longitude: 0, height: Self.heightMeters)
            let expected = Self.polarRadiusKm + Self.heightMeters / 1_000

            let ofDate = try observer.vector(at: Self.time, equator: .ofDate)
            let axial = ofDate.z * Self.kilometersPerAU
            let offAxis = hypot(ofDate.x, ofDate.y) * Self.kilometersPerAU
            #expect(
                abs(axial - Double(signOf: latitude, magnitudeOf: expected)) < Self.toleranceKm,
                "z = \(axial) km"
            )
            #expect(offAxis < Self.toleranceKm, "\(offAxis) km off the axis")

            let radius = try observer.vector(at: Self.time, equator: .j2000).magnitude * Self.kilometersPerAU
            #expect(abs(radius - expected) < Self.toleranceKm, "J2000: \(radius) km, expected \(expected) km")
        }

        /// Earth rotation angle at J2000 UT (`ut` 0): 360° × 0.7790572732640,
        /// from IAU 2000 Resolution B1.8.
        static let rotationAngleAtJ2000 = 360 * 0.779_057_273_264_0

        /// Constant term of the IAU 2006 Greenwich mean sidereal time,
        /// GMST = ERA + 0.014506″ + 4612.156534″ t + … (Capitaine, Wallace &
        /// Chapront 2003, A&A 412, 567).
        static let siderealOffsetDegrees = 0.014_506 / 3_600

        /// 0.005″. At `ut` 0, TT is about 64 s later, so the precession and
        /// GMST rate terms add under 1e-4″. Converting to J2000 removes
        /// nutation, which cancels the equation of the equinoxes to first order
        /// and leaves under 0.001″. A 1 s sidereal time error is 15″.
        static let rightAscensionToleranceDegrees = 0.005 / 3_600

        @Test(
            "At J2000 an equatorial observer's J2000 right ascension is the Earth rotation angle plus longitude",
            arguments: [0.0, 30.0, -120.0, 179.5]
        )
        func rightAscensionFollowsEarthRotationAngle(longitude: Double) throws {
            let observer = Observer(latitude: 0, longitude: longitude)
            let vector = try observer.vector(at: AstroTime(ut: 0), equator: .j2000)

            let rightAscension = atan2(vector.y, vector.x) * 180 / .pi
            let expected = Self.rotationAngleAtJ2000 + Self.siderealOffsetDegrees + longitude
            let difference = IndependentReferenceMath.wrappedDifference(rightAscension, expected)
            #expect(
                abs(difference) < Self.rightAscensionToleranceDegrees,
                "right ascension \(rightAscension)°, expected \(expected)°, off by \(difference * 3_600)″"
            )
        }
    }

    // MARK: - Geocentric Observer

    /// `Observer.geocentric` sits the observer model's equatorial radius
    /// below the surface at latitude 0, so it is at Earth's centre (#154).
    @Test("The geocentric observer's vector has zero length", arguments: [EquatorDate.j2000, .ofDate])
    func geocentricObserverAtCentre(equator: EquatorDate) throws {
        let time = AstroTime(year: 2_025, month: 1, day: 1)
        #expect(try Observer.geocentric.vector(at: time, equator: equator).magnitude == 0)
    }

    /// With the observer at the centre, the default-observer equatorial
    /// position is the geocentric vector's. 1e-12 degrees and 1e-15 AU allow
    /// for the two paths converting the same vector to angles separately.
    @Test(
        "Default-observer equatorial coordinates are the geocentric vector's",
        arguments: [CelestialBody.moon, .mars]
    )
    func defaultObserverIsGeocentric(body: CelestialBody) throws {
        for hour in [0, 6] {
            let time = AstroTime(year: 2_025, month: 1, day: 1, hour: hour)
            let fromObserver = try body.equatorial(at: time)
            let fromVector = try body.geocentricPosition(at: time).toEquatorial()
            #expect(abs(fromObserver.rightAscension - fromVector.rightAscension) * 15 <= 1e-12, "\(body) \(hour)h")
            #expect(abs(fromObserver.declination - fromVector.declination) <= 1e-12, "\(body) \(hour)h")
            #expect(abs(fromObserver.distance - fromVector.distance) <= 1e-15, "\(body) \(hour)h")
        }
    }

    // MARK: - Reverse Observer from Vector

    @Test("Vector-to-observer roundtrip preserves location")
    func vectorObserverRoundtrip() throws {
        let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)
        let original = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)
        let vec = try original.vector(at: testTime, equator: .ofDate)
        let restored = Observer.from(vector: vec, equatorDate: .ofDate)

        #expect(abs(restored.latitude - original.latitude) < 0.01)
        #expect(abs(restored.longitude - original.longitude) < 0.01)
        #expect(abs(restored.height - original.height) < 100)
    }

    @Test("Vector-to-observer works with J2000 frame")
    func vectorObserverJ2000() throws {
        let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)
        let original = Observer(latitude: 51.4769, longitude: -0.0005, height: 48)
        let vec = try original.vector(at: testTime, equator: .j2000)
        let restored = Observer.from(vector: vec, equatorDate: .j2000)

        #expect(abs(restored.latitude - original.latitude) < 0.01)
        #expect(abs(restored.longitude - original.longitude) < 0.5)
    }
}

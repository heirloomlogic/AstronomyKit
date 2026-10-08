//
//  EngineStarTests.swift
//  AstronomyKit
//
//  Fixed-star values and native position calculations.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine fixed stars")
struct EngineStarTests {
    typealias Star = Engine.Star

    static let time = Engine.Time(ut: 9_496.374_023_437_5, tt: 9_496.375, deltaTModel: .espenakMeeus)
    static let spica = Star(rightAscension: 13.419_883_06, declination: -11.161_319_44, distance: 250)

    @Test("Every native fixed-star calculation matches the archived SOFA example")
    func sofaReference() throws {
        let reference = try #require(IndependentReferenceArchive.shared.fixedStars.first)
        let star = Star(
            rightAscension: reference.rightAscensionHours,
            declination: reference.declinationDegrees,
            distance: reference.distanceLightYears
        )
        let time = Engine.Time(
            ut: reference.utJulianDate - 2_451_545,
            tt: reference.ttJulianDate - 2_451_545,
            deltaTModel: .espenakMeeus
        )
        let observer = Observer(
            latitude: reference.latitudeDegrees,
            longitude: reference.longitudeDegrees,
            height: reference.heightMeters
        )
        let toleranceArcminutes = reference.sampledToleranceArcseconds / 60

        let heliocentric = try star.heliocentricPosition(at: time)
        let catalog = try Engine.Spherical(heliocentric)
        #expect(abs(catalog.longitude / 15 - reference.rightAscensionHours) < 1e-14)
        #expect(abs(catalog.latitude - reference.declinationDegrees) < 1e-14)
        #expect(catalog.distance == reference.distanceLightYears * Star.astronomicalUnitsPerLightYear)

        let geocentric = try Engine.Positions.coordinates(
            star.geocentricPosition(at: time, aberration: .corrected)
        )
        expectEquatorial(
            geocentric,
            rightAscension: reference.j2000RightAscensionHours,
            declination: reference.j2000DeclinationDegrees,
            toleranceArcminutes: toleranceArcminutes
        )
        expectEquatorial(
            try star.equatorial(at: time, from: .geocentric, equatorDate: .j2000),
            rightAscension: reference.j2000RightAscensionHours,
            declination: reference.j2000DeclinationDegrees,
            toleranceArcminutes: toleranceArcminutes
        )
        expectEquatorial(
            try star.equatorial(at: time, from: .geocentric, equatorDate: .ofDate),
            rightAscension: reference.ofDateRightAscensionHours,
            declination: reference.ofDateDeclinationDegrees,
            toleranceArcminutes: toleranceArcminutes
        )
        expectEquatorial(
            try star.equatorial(at: time, from: observer, equatorDate: .ofDate),
            rightAscension: reference.topocentricRightAscensionHours,
            declination: reference.topocentricDeclinationDegrees,
            toleranceArcminutes: toleranceArcminutes
        )

        let ecliptic = try star.ecliptic(at: time)
        let eclipticError =
            IndependentReferenceMath.sphericalDistanceDegrees(
                latitude1: ecliptic.latitude,
                longitude1: ecliptic.longitude,
                latitude2: reference.eclipticLatitudeDegrees,
                longitude2: reference.eclipticLongitudeDegrees
            ) * 60
        #expect(eclipticError <= toleranceArcminutes)

        let horizontal = try star.horizontal(at: time, from: observer, refraction: .none)
        let horizontalError =
            IndependentReferenceMath.sphericalDistanceDegrees(
                latitude1: horizontal.altitude,
                longitude1: horizontal.azimuth,
                latitude2: reference.unrefractedAltitudeDegrees,
                longitude2: reference.azimuthDegrees
            ) * 60
        #expect(horizontalError <= toleranceArcminutes)
        #expect(reference.sampledMaximumResidualArcseconds < reference.sampledToleranceArcseconds)
    }

    private func expectEquatorial(
        _ actual: Engine.Equatorial,
        rightAscension: Double,
        declination: Double,
        toleranceArcminutes: Double
    ) {
        let error = IndependentReferenceMath.angularSeparationArcminutes(
            raDegrees1: actual.rightAscension * 15,
            decDegrees1: actual.declination,
            raDegrees2: rightAscension * 15,
            decDegrees2: declination
        )
        #expect(error <= toleranceArcminutes)
    }

    @Test("Catalog coordinates form an immutable heliocentric J2000 value")
    func heliocentricCatalogValue() throws {
        let vector = try Self.spica.heliocentricPosition(at: Self.time)
        let sphere = try Engine.Spherical(vector)

        #expect(abs(sphere.longitude / 15 - Self.spica.rightAscension) < 1e-14)
        #expect(abs(sphere.latitude - Self.spica.declination) < 1e-14)
        #expect(sphere.distance == Self.spica.distance * Star.astronomicalUnitsPerLightYear)
        #expect(vector.time.ut == Self.time.ut)
        #expect(vector.time.tt == Self.time.tt)
        #expect(vector.time.deltaTModel == Self.time.deltaTModel)
    }

    @Test(
        "Invalid catalog definitions are rejected before calculation",
        arguments: [
            Star(rightAscension: -.infinity, declination: 0, distance: 1),
            Star(rightAscension: -Double.leastNonzeroMagnitude, declination: 0, distance: 1),
            Star(rightAscension: 24, declination: 0, distance: 1),
            Star(rightAscension: .nan, declination: 0, distance: 1),
            Star(rightAscension: 0, declination: -Double(90).nextUp, distance: 1),
            Star(rightAscension: 0, declination: Double(90).nextUp, distance: 1),
            Star(rightAscension: 0, declination: .infinity, distance: 1),
            Star(rightAscension: 0, declination: 0, distance: Double(1).nextDown),
            Star(rightAscension: 0, declination: 0, distance: .nan),
        ])
    func invalidDefinition(_ star: Star) {
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try star.heliocentricPosition(at: Self.time)
        }
    }

    @Test("Definitions have value equality and stable hashing")
    func valueSemantics() {
        let copy = Star(
            rightAscension: Self.spica.rightAscension,
            declination: Self.spica.declination,
            distance: Self.spica.distance
        )
        #expect(copy == Self.spica)
        #expect(Set([copy, Self.spica]).count == 1)
    }

    @Test(
        "Invalid observers are rejected before topocentric calculation",
        arguments: [
            Observer(latitude: -.infinity, longitude: 0),
            Observer(latitude: -Double(90).nextUp, longitude: 0),
            Observer(latitude: Double(90).nextUp, longitude: 0),
            Observer(latitude: 0, longitude: .nan),
            Observer(latitude: 0, longitude: 0, height: .infinity),
        ]
    )
    func invalidObserver(_ observer: Observer) {
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try Self.spica.equatorial(at: Self.time, from: observer, equatorDate: .j2000)
        }
        #expect(throws: AstronomyError.invalidParameter) {
            _ = try Self.spica.horizontal(at: Self.time, from: observer, refraction: .none)
        }
    }

    @Test("Geocentric position preserves parallax and the annual-aberration approximation")
    func geocentricPosition() throws {
        let catalog = try Self.spica.heliocentricPosition(at: Self.time)
        let earthPosition = try Engine.Planet.earth.heliocentricPosition(at: Self.time)
        let earthState = try Engine.Planet.earth.heliocentricState(at: Self.time)
        let geometric = try Self.spica.geocentricPosition(at: Self.time, aberration: .none)
        let apparent = try Self.spica.geocentricPosition(at: Self.time, aberration: .corrected)
        let relative = SIMD3(catalog.x - earthPosition.x, catalog.y - earthPosition.y, catalog.z - earthPosition.z)
        let distance = (relative * relative).sum().squareRoot()
        let expectedApparent = relative + earthState.velocityVector * (distance / Engine.speedOfLightAUPerDay)

        #expect(SIMD3(geometric.x, geometric.y, geometric.z) == relative)
        #expect(SIMD3(apparent.x, apparent.y, apparent.z) == expectedApparent)
        #expect(apparent.time.ut == Self.time.ut && apparent.time.tt == Self.time.tt)
    }

    @Test("Equatorial calculations preserve J2000, of-date, and topocentric frames")
    func equatorialFrames() throws {
        let observer = Observer(latitude: 35.595, longitude: -82.5572, height: 812)
        let geocentric = try Self.spica.geocentricPosition(at: Self.time, aberration: .corrected)
        let site = Engine.Observers.vector(observer, at: Self.time)
        let topocentric = Engine.Vector<Engine.EQJ>(
            x: geocentric.x - site.x,
            y: geocentric.y - site.y,
            z: geocentric.z - site.z,
            time: Self.time
        )
        let expectedJ2000 = try Engine.Equatorial(topocentric)
        let expectedOfDate = try Engine.Equatorial(Engine.FrameRotation.eqjToEqd(Self.time).apply(to: topocentric))

        let j2000 = try Self.spica.equatorial(at: Self.time, from: observer, equatorDate: .j2000)
        let ofDate = try Self.spica.equatorial(at: Self.time, from: observer, equatorDate: .ofDate)

        #expect(j2000.rightAscension == expectedJ2000.rightAscension)
        #expect(j2000.declination == expectedJ2000.declination)
        #expect(j2000.distance == expectedJ2000.distance)
        #expect(ofDate.rightAscension == expectedOfDate.rightAscension)
        #expect(ofDate.declination == expectedOfDate.declination)
        #expect(ofDate.distance == expectedOfDate.distance)
    }

    @Test("Ecliptic coordinates use the apparent geocentric vector and true ecliptic of date")
    func eclipticOfDate() throws {
        let position = try Self.spica.geocentricPosition(at: Self.time, aberration: .corrected)
        let expected = Engine.Ecliptic(position)
        let actual = try Self.spica.ecliptic(at: Self.time)

        #expect(actual.longitude == expected.longitude)
        #expect(actual.latitude == expected.latitude)
        #expect(actual.vector.x == expected.vector.x)
        #expect(actual.vector.y == expected.vector.y)
        #expect(actual.vector.z == expected.vector.z)
    }

    @Test("Horizontal coordinates use apparent topocentric equatorial coordinates of date")
    func horizontalCoordinates() throws {
        let observer = Observer(latitude: 35.595, longitude: -82.5572, height: 812)
        let equatorial = try Self.spica.equatorial(at: Self.time, from: observer, equatorDate: .ofDate)
        let expected = Engine.Horizontal(
            time: Self.time,
            observer: observer,
            rightAscension: equatorial.rightAscension,
            declination: equatorial.declination,
            refraction: .normal
        )
        let actual = try Self.spica.horizontal(at: Self.time, from: observer, refraction: .normal)

        #expect(actual.azimuth == expected.azimuth)
        #expect(actual.altitude == expected.altitude)
        #expect(actual.rightAscension == expected.rightAscension)
        #expect(actual.declination == expected.declination)
    }

    @Test("Calculation rejects times outside the accepted ephemeris range")
    func acceptedTimeRange() {
        for tt in [-Engine.acceptedTTDays.nextUp, Engine.acceptedTTDays.nextUp, .nan, .infinity] {
            let time = Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
            #expect(throws: AstronomyError.badTime) {
                _ = try Self.spica.geocentricPosition(at: time, aberration: .corrected)
            }
        }
    }

    @Test("A finite light-year distance whose AU conversion overflows is a bad time result")
    func distanceOverflow() {
        let star = Star(rightAscension: 0, declination: 0, distance: .greatestFiniteMagnitude)
        #expect(throws: AstronomyError.badTime) {
            _ = try star.heliocentricPosition(at: Self.time)
        }
    }
}

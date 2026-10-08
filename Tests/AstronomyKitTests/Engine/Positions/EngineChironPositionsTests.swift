//
//  EngineChironPositionsTests.swift
//  AstronomyKit
//
//  Chiron seen from Earth's center: against the Horizons observer rows, its
//  composition, and the light time at the start of its span (#197).
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine Chiron positions")
struct EngineChironPositionsTests {
    typealias Positions = Engine.Positions

    static let rows = IndependentReferenceArchive.shared.chironObservations

    /// 1900-01-01 03:00 UT, the first row's time, and Chiron's light-time
    /// position then, which `spanStart` also reads: integrating a century
    /// back from the 2000 anchor takes seconds in Debug.
    static let firstRowTime = Engine.Time(ut: Engine.Chiron.earliestUT + 3.0 / 24, deltaTModel: .espenakMeeus)
    static let firstRow = Result { try Positions.chironGeocentricPosition(at: firstRowTime) }

    /// Horizons' astrometric direction, and its apparent ecliptic of date,
    /// which differs from the engine's, without aberration like the public
    /// API's, by up to κ = 20.5″; both within the rows' 1′. The range is
    /// within 0.002 AU, the drift `NATIVE_ENGINE.md` records for Chiron's
    /// heliocentric state a century from its anchors (254,000 km in 1900),
    /// rounded up: a measured bound, not a published accuracy. Measured: 0.49′
    /// and 5.6e-4 AU at most, in 1900.
    @Test("Chiron against the Horizons observer rows from 1900 to 2100")
    func observerRows() throws {
        #expect(Self.rows.count == 6)
        for row in Self.rows {
            let time = IndependentReferenceDate.engine(row.utc)
            // One integration per row: the coordinates are this vector's, as
            // `composition` checks.
            let vector =
                abs(time.ut - Self.firstRowTime.ut) < 1e-9
                ? try Self.firstRow.get() : try Positions.chironGeocentricPosition(at: time)
            let equatorial = try Engine.Equatorial(vector)
            let arcminutes = IndependentReferenceMath.angularSeparationArcminutes(
                raDegrees1: equatorial.rightAscension * 15, decDegrees1: equatorial.declination,
                raDegrees2: row.rightAscensionDegrees, decDegrees2: row.declinationDegrees)
            #expect(arcminutes <= row.angularToleranceArcminutes, "\(row.utc): \(arcminutes)′")
            let ecliptic = Engine.Ecliptic(vector)
            let longitude = IndependentReferenceMath.wrappedDifference(ecliptic.longitude, row.eclipticLongitudeDegrees)
            #expect(abs(longitude) * 60 <= row.angularToleranceArcminutes, "\(row.utc)")
            #expect(abs(ecliptic.latitude - row.eclipticLatitudeDegrees) * 60 <= row.angularToleranceArcminutes)
            #expect(abs(equatorial.distance - row.apparentRangeAU) <= 0.002, "\(row.utc): \(equatorial.distance) AU")
        }
    }

    @Test("Chiron's coordinates are its light-time position's; its geocentric state is Chiron's less Earth's")
    func composition() throws {
        let time = Engine.Time(tt: 9_500.75, deltaTModel: .espenakMeeus)
        let vector = try Positions.chironGeocentricPosition(at: time)
        let lightTime = vector.length / Engine.speedOfLightAUPerDay
        #expect(abs(vector.time.tt - time.adding(days: -lightTime).tt) < 1e-9)

        let equatorial = try Positions.chironEquatorial(at: time)
        let expected = try Engine.Equatorial(vector)
        #expect(equatorial.rightAscension == expected.rightAscension && equatorial.declination == expected.declination)
        #expect(equatorial.distance == expected.distance)
        let ecliptic = try Positions.chironEcliptic(at: time)
        #expect(ecliptic.longitude == Engine.Ecliptic(vector).longitude)
        #expect(ecliptic.vector.time.tt == vector.time.tt)

        let state = try Positions.chironGeocentricState(at: time)
        let chiron = try Engine.Chiron.heliocentricState(at: time)
        let earth = try Positions.heliocentricState(of: .earth, at: time)
        #expect(state.positionVector == chiron.positionVector - earth.positionVector)
        #expect(state.velocityVector == chiron.velocityVector - earth.velocityVector)
        #expect(state.time.tt == time.tt)

        let horizontal = try Positions.chironHorizontal(at: time, from: ashevilleObserver, refraction: .normal)
        var ofDate = vector
        ofDate.time = time
        let rotated = try Engine.Equatorial(Engine.FrameRotation.eqjToEqd(time).apply(to: ofDate))
        let expectedHorizontal = Engine.Horizontal(
            time: time, observer: ashevilleObserver, rightAscension: rotated.rightAscension,
            declination: rotated.declination, refraction: .normal)
        #expect(horizontal.azimuth == expectedHorizontal.azimuth && horizontal.altitude == expectedHorizontal.altitude)
    }

    /// The observation span starts at 1900-01-01 00:00 UT. At 01:00 UT light
    /// left Chiron about 1.56 hours earlier, so the internal evaluation is
    /// before the span even though the requested apparent position is inside.
    @Test("Apparent positions accept the first hour of Chiron's span", arguments: DeltaTModel.allCases)
    func spanStart(model: DeltaTModel) throws {
        let start = Engine.Time(ut: Engine.Chiron.earliestUT, deltaTModel: model).tt
        let early = Engine.Time(ut: Engine.Chiron.earliestUT + 1.0 / 24, deltaTModel: model)
        try Engine.Chiron.checkSupported(early)
        let vector = try Self.firstRow.get()
        #expect(vector.time.tt >= start)
        let lightTime = Self.firstRowTime.tt - vector.time.tt
        #expect(early.tt - lightTime < start && early.tt > start, "light time \(lightTime * 24) h")
        #expect(abs(lightTime * 24 - 1.560) < 0.005, "light time \(lightTime * 24) h")

        let earlyVector = try Positions.chironGeocentricPosition(at: early)
        #expect(earlyVector.time.tt < start)
        let equatorial = try Engine.Equatorial(earlyVector)
        let ecliptic = Engine.Ecliptic(earlyVector)
        var ofDate = earlyVector
        ofDate.time = early
        let rotated = try Engine.Equatorial(Engine.FrameRotation.eqjToEqd(early).apply(to: ofDate))
        let horizontal = Engine.Horizontal(
            time: early, observer: ashevilleObserver, rightAscension: rotated.rightAscension,
            declination: rotated.declination, refraction: .none)
        #expect(equatorial.rightAscension.isFinite && equatorial.declination.isFinite)
        #expect(ecliptic.longitude.isFinite && ecliptic.latitude.isFinite)
        #expect(horizontal.azimuth.isFinite && horizontal.altitude.isFinite)
    }
}

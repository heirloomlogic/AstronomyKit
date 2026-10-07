//
//  EnginePlanetHorizonsTests.swift
//  AstronomyKit
//
//  The Swift planet functions under the same JPL Horizons checks as the
//  public JPLValidationTests planet suites and the geocentric records of
//  DistanceAccuracyTests, with the same allowances.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine planets against JPL Horizons, geocentric and topocentric")
struct EnginePlanetHorizonsTests {
    /// A body the planet functions cover: a planet, or the Sun as the origin.
    enum Body: Sendable, CustomTestStringConvertible {
        case sun
        case planet(Engine.Planet)

        var testDescription: String {
            switch self {
            case .sun: "Sun"
            case .planet(let planet): "\(planet)"
            }
        }
    }

    /// The astrometric geocentric EQJ vector, Horizons' definition: the body
    /// at the time light left it, minus Earth at `time`, with no aberration.
    /// The light time comes from `Engine.LightTravel`.
    static func geocentric(_ body: Body, at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
        let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
        return try Engine.LightTravel.correct(at: time) { backdated in
            var target = Engine.Vector<Engine.EQJ>(x: 0, y: 0, z: 0, time: backdated)
            if case .planet(let planet) = body {
                target = try planet.heliocentricPosition(at: backdated)
            }
            return Engine.Vector(
                x: target.x - earth.x, y: target.y - earth.y, z: target.z - earth.z, time: backdated)
        }
    }

    /// 00:00 UT on the reference's date, with the Espenak-Meeus Delta T.
    static func time(_ reference: JPLReferencePoint) -> Engine.Time {
        let ut = Engine.Time.days(
            year: reference.year, month: reference.month, day: reference.day, hour: 0, minute: 0, second: 0)
        return Engine.Time(ut: ut, deltaTModel: .espenakMeeus)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let body: Body
        let references: [JPLReferencePoint]
        var testDescription: String { body.testDescription }

        /// The suite's tolerance: 1.5′ for Neptune and 1′ for the others.
        var toleranceArcminutes: Double {
            if case .planet(.neptune) = body { return outerPlanetToleranceArcminutes }
            return AstronomyKitTests.toleranceArcminutes
        }
    }

    /// The geocentric suites of `JPLValidationTests`.
    static let geocentricCases: [Case] = [
        Case(body: .sun, references: SunValidationTests.referenceData),
        Case(body: .planet(.mercury), references: MercuryValidationTests.referenceData),
        Case(body: .planet(.venus), references: VenusValidationTests.referenceData),
        Case(body: .planet(.mars), references: MarsValidationTests.referenceData),
        Case(body: .planet(.jupiter), references: JupiterValidationTests.referenceData),
        Case(body: .planet(.saturn), references: SaturnValidationTests.referenceData),
        Case(body: .planet(.uranus), references: UranusValidationTests.referenceData),
        Case(body: .planet(.neptune), references: NeptuneValidationTests.referenceData),
    ]

    /// The planet suites of `AshevilleValidationTests`.
    static let ashevilleCases: [Case] = [
        Case(body: .planet(.mercury), references: AshevilleValidationTests.mercuryData),
        Case(body: .planet(.venus), references: AshevilleValidationTests.venusData),
        Case(body: .planet(.mars), references: AshevilleValidationTests.marsData),
        Case(body: .planet(.jupiter), references: AshevilleValidationTests.jupiterData),
        Case(body: .planet(.saturn), references: AshevilleValidationTests.saturnData),
        Case(body: .planet(.uranus), references: AshevilleValidationTests.uranusData),
        Case(body: .planet(.neptune), references: AshevilleValidationTests.neptuneData),
    ]

    /// The geocentric records of `distance-fixtures.json` for the Sun and the
    /// planets the functions cover, with their times on the fixture's TT.
    static let geocentricRecords: [(body: Body, time: Engine.Time, reference: DistanceReferenceArchive.Reference)] =
        DistanceReferenceArchive.shared.references.compactMap { reference in
            guard reference.mode == "geocentric" else { return nil }
            let time = Engine.Time(tt: reference.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
            if reference.body == "Sun" { return (.sun, time, reference) }
            guard let celestial = CelestialBody.allCases.first(where: { $0.name == reference.body }),
                let planet = Engine.Planet(celestial)
            else { return nil }
            return (.planet(planet), time, reference)
        }

    static func separation(_ vector: Engine.Vector<Engine.EQJ>, _ reference: JPLReferencePoint) throws -> Double {
        let equatorial = try Engine.Equatorial(vector)
        return angularSeparation(
            ra1: reference.rightAscension, dec1: reference.declination,
            ra2: equatorial.rightAscension, dec2: equatorial.declination)
    }

    @Test("Geocentric J2000 positions within the JPLValidationTests tolerances", arguments: geocentricCases)
    func geocentricPositions(testCase: Case) throws {
        #expect(testCase.references.count == 4)
        for reference in testCase.references {
            let vector = try Self.geocentric(testCase.body, at: Self.time(reference))
            let arcminutes = try Self.separation(vector, reference)
            #expect(arcminutes <= testCase.toleranceArcminutes, "\(reference.year)-\(reference.month)-\(reference.day)")
        }
    }

    @Test(
        "Topocentric J2000 positions from Asheville within the JPLValidationTests tolerances", arguments: ashevilleCases
    )
    func ashevillePositions(testCase: Case) throws {
        #expect(testCase.references.count == 4)
        for reference in testCase.references {
            let time = Self.time(reference)
            let geocentric = try Self.geocentric(testCase.body, at: time)
            let observer = Engine.Observers.vector(ashevilleObserver, at: time)
            let topocentric = Engine.Vector<Engine.EQJ>(
                x: geocentric.x - observer.x, y: geocentric.y - observer.y, z: geocentric.z - observer.z,
                time: geocentric.time)
            let arcminutes = try Self.separation(topocentric, reference)
            #expect(arcminutes <= testCase.toleranceArcminutes, "\(reference.year)-\(reference.month)-\(reference.day)")
        }
    }

    /// Horizons' geocentric ranges are light-time corrected with no
    /// aberration, as `geocentric(_:at:)` is.
    @Test("Geocentric distances within the DistanceAccuracyTests allowances")
    func geocentricDistances() throws {
        // Sun, Mercury, Venus, Mars, Jupiter, Saturn, Uranus and Neptune, 134 each.
        #expect(Self.geocentricRecords.count == 8 * 134)
        for (body, time, reference) in Self.geocentricRecords {
            let range = try Self.geocentric(body, at: time).length
            let errorKm = abs(range - reference.referenceRangeAU) * Engine.kilometersPerAU
            #expect(
                errorKm <= reference.allowedErrorKm,
                "\(reference.body) JD TT \(reference.julianDateTT): \(errorKm) km, allowance \(reference.allowedErrorKm) km"
            )
        }
    }

    @Test("The checks fail for the wrong body, a day's error or the heliocentric range")
    func negativeControls() throws {
        let reference = MarsValidationTests.referenceData[0]
        let time = Self.time(reference)
        #expect(try Self.separation(Self.geocentric(.planet(.jupiter), at: time), reference) > toleranceArcminutes)
        #expect(
            try Self.separation(Self.geocentric(.planet(.mars), at: time.adding(days: 1)), reference)
                > toleranceArcminutes)
        let (_, recordTime, record) = try #require(Self.geocentricRecords.first { $0.reference.body == "Mars" })
        let heliocentric = try Engine.Planet.mars.heliocentricDistance(at: recordTime)
        #expect(abs(heliocentric - record.referenceRangeAU) * Engine.kilometersPerAU > record.allowedErrorKm)
    }
}

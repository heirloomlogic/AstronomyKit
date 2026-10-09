//
//  EngineMoonHorizonsTests.swift
//  AstronomyKit
//
//  The Swift Moon against JPL Horizons: the public Moon suites' references
//  and allowances, and Horizons vectors beyond the DE440 Moon's span.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine Moon against JPL Horizons")
struct EngineMoonHorizonsTests {
    static func time(_ reference: JPLReferencePoint) -> Engine.Time { EnginePlanetHorizonsTests.time(reference) }

    /// The astrometric J2000 direction from `observer`, Horizons'
    /// definition: the Moon at the time light left it, less the observer at
    /// `time`.
    static func astrometric(from observer: Observer?, at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
        let origin = observer.map { Engine.Observers.vector($0, at: time) }
        return try Engine.LightTravel.correct(at: time) { backdated in
            let moon = try Engine.Moon.geocentricPosition(at: backdated)
            guard let origin else { return moon }
            return Engine.Vector(x: moon.x - origin.x, y: moon.y - origin.y, z: moon.z - origin.z, time: backdated)
        }
    }

    static func separation(_ vector: Engine.Vector<Engine.EQJ>, _ reference: JPLReferencePoint) throws -> Double {
        try EnginePlanetHorizonsTests.separation(vector, reference)
    }

    @Test("The JPLValidationTests geocentric Moon suite within its 1′")
    func geocentric() throws {
        #expect(MoonValidationTests.referenceData.count == 4)
        for reference in MoonValidationTests.referenceData {
            let arcminutes = try Self.separation(Self.astrometric(from: nil, at: Self.time(reference)), reference)
            #expect(arcminutes <= toleranceArcminutes, "\(reference.month)-\(reference.day): \(arcminutes)′")
        }
    }

    /// The Moon's parallax from Asheville is close to a degree, so this
    /// check fails without the observer (see `negativeControls`).
    @Test("The JPLValidationTests Asheville Moon suite within its 1′")
    func asheville() throws {
        #expect(AshevilleValidationTests.moonData.count == 4)
        for reference in AshevilleValidationTests.moonData {
            let vector = try Self.astrometric(from: ashevilleObserver, at: Self.time(reference))
            let arcminutes = try Self.separation(vector, reference)
            #expect(arcminutes <= toleranceArcminutes, "\(reference.month)-\(reference.day): \(arcminutes)′")
        }
    }

    /// The Moon records of `distance-fixtures.json`: Horizons' geometric
    /// geocentric ranges from 1901 to 2100, as `DistanceAccuracyTests`
    /// reads them.
    static let distanceRecords = DistanceReferenceArchive.shared.references.filter {
        $0.body == "Moon" && $0.mode == "geocentric"
    }

    @Test("Geocentric distances within the DistanceAccuracyTests allowances")
    func distances() throws {
        #expect(Self.distanceRecords.count == 134)
        for reference in Self.distanceRecords {
            let time = Engine.Time(tt: reference.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
            let range = try Engine.Moon.geocentricPosition(at: time).length
            let errorKm = abs(range - reference.referenceRangeAU) * Engine.kilometersPerAU
            #expect(
                errorKm <= reference.allowedErrorKm,
                "JD TT \(reference.julianDateTT): \(errorKm) km, allowance \(reference.allowedErrorKm) km")
        }
    }

    /// The Horizons observer rows at 1900, 2000 and 2100 that
    /// `AuditValidationTests.jplGeocentricObservation` reads, with its 1′.
    /// They are apparent positions, which differ from the geometric ones by
    /// up to about 20″ of aberration.
    @Test("The ICRF direction and the ecliptic of date against the Horizons observer rows")
    func observerRows() throws {
        let rows = IndependentReferenceArchive.shared.observations.filter { $0.body == "moon" }
        #expect(rows.count == 3)
        for row in rows {
            let ut = IndependentReferenceDate.civil(row.utc).universalTime
            let time = Engine.Time(ut: ut, deltaTModel: .espenakMeeus)
            let equatorial = try Engine.Equatorial(Engine.Moon.geocentricPosition(at: time))
            let arcminutes = IndependentReferenceMath.angularSeparationArcminutes(
                raDegrees1: equatorial.rightAscension * 15, decDegrees1: equatorial.declination,
                raDegrees2: row.rightAscensionDegrees, decDegrees2: row.declinationDegrees)
            #expect(arcminutes <= row.angularToleranceArcminutes, "\(row.utc): \(arcminutes)′")
            let ecliptic = try Engine.Moon.eclipticPosition(at: time)
            let longitude = IndependentReferenceMath.wrappedDifference(ecliptic.longitude, row.eclipticLongitudeDegrees)
            #expect(abs(longitude) * 60 <= row.angularToleranceArcminutes, "\(row.utc)")
            #expect(abs(ecliptic.latitude - row.eclipticLatitudeDegrees) * 60 <= row.angularToleranceArcminutes)
        }
    }

    // MARK: - Beyond the DE440 Moon

    /// Horizons' geometric Moon vectors in `reference-fixtures.json`, from
    /// `sources/horizons/moon-vector.json`: 30 dates from 2002 BCE to 6000 CE,
    /// eleven of them within 40 days of 1900-01-01 and 2131-01-01, where the
    /// blends are.
    static let vectors = IndependentReferenceArchive.shared.vectors.filter { $0.body == "moon" }

    /// The samples, by Julian date TDB, where the lunar series is more than
    /// 1′ from Horizons: the 13 from 2002 BCE to 999 CE and from 3000 CE to
    /// 6000 CE (#184).
    static let beyondSeriesAccuracy: Set<Double> = [
        990_546.0, 990_910.5, 1_173_170.5, 1_355_795.5, 1_538_420.5, 1_721_045.5, 1_903_670.5, 2_086_295.5,
        2_816_795.5, 3_182_045.5, 3_547_295.5, 3_912_180.5, 3_912_544.0,
    ]

    /// The allowance `DistanceAccuracyTests` applies to every Moon record.
    static let distanceAllowanceKm = 28.689

    /// The engine's position against one Horizons vector: the angle in
    /// arcminutes and the range error in km. Horizons gives the time in TDB
    /// and the vector on ICRF axes; the engine takes TT and gives EQJ.
    static func errors(
        _ reference: IndependentReferenceArchive.Vector, legacy: Bool = false
    ) throws -> (arcminutes: Double, km: Double) {
        let tdb = reference.julianDateTDB - 2_451_545
        let tt = tdb - Engine.TDB.offsetSeconds(tt: tdb) / 86_400
        let time = PlanetTestSupport.time(tt: tt)
        let moon: Engine.Vector<Engine.EQJ>
        if legacy {
            let coordinates = Engine.Moon.rectangular(Engine.LunarSeries.coordinates(centuries: tt / 36_525))
            let eqj = Engine.Precession.rotation(tt: tt).inverse.apply(
                to: Engine.Moon.meanEquatorToEcliptic(tt: tt).inverse.apply(to: coordinates))
            moon = Engine.Vector(x: eqj.x, y: eqj.y, z: eqj.z, time: time)
        } else {
            moon = try Engine.Moon.geocentricPosition(at: time)
        }
        let icrs = reference.positionAU
        let published = Engine.FrameBias.icrsToEqj.apply(to: SIMD3(icrs[0], icrs[1], icrs[2]))
        let expected = Engine.Vector<Engine.EQJ>(x: published.x, y: published.y, z: published.z, time: time)
        return (try moon.angle(to: expected) * 60, abs(moon.length - expected.length) * Engine.kilometersPerAU)
    }

    @Test("Through the blends and DE441 from 1499 to 2500, within 1′ and the Moon's distance allowance")
    func beyondTheTable() throws {
        #expect(Self.vectors.count == 30)
        let checked = Self.vectors.filter { !Self.beyondSeriesAccuracy.contains($0.julianDateTDB) }
        #expect(checked.count == 17)
        for reference in checked {
            let (arcminutes, km) = try Self.errors(reference)
            #expect(arcminutes <= toleranceArcminutes, "\(reference.tdb): \(arcminutes)′")
            #expect(km <= Self.distanceAllowanceKm, "\(reference.tdb): \(km) km")
        }
    }

    @Test(
        "The legacy series still used by public C APIs misses 1′ (#184, #96)", arguments: beyondSeriesAccuracy.sorted())
    func farFromJ2000(julianDateTDB: Double) throws {
        let reference = try #require(Self.vectors.first { $0.julianDateTDB == julianDateTDB })
        let (arcminutes, km) = try Self.errors(reference, legacy: true)
        withKnownIssue("#184: the lunar series is more than 1′ from DE441 before 1500 and after 2500") {
            #expect(arcminutes <= toleranceArcminutes, "\(reference.tdb): \(arcminutes)′")
            #expect(km <= Self.distanceAllowanceKm, "\(reference.tdb): \(km) km")
        }
    }

    @Test("The checks fail without the observer, a day off, or with the wrong distance")
    func negativeControls() throws {
        let reference = AshevilleValidationTests.moonData[0]
        let time = Self.time(reference)
        #expect(try Self.separation(Self.astrometric(from: nil, at: time), reference) > toleranceArcminutes)
        let geocentric = MoonValidationTests.referenceData[0]
        #expect(
            try Self.separation(Self.astrometric(from: nil, at: Self.time(geocentric).adding(days: 1)), geocentric)
                > toleranceArcminutes)
        let record = try #require(Self.distanceRecords.first)
        let recordTime = Engine.Time(tt: record.julianDateTT - 2_451_545 + 1, deltaTModel: .jplHorizons)
        let range = try Engine.Moon.geocentricPosition(at: recordTime).length
        #expect(abs(range - record.referenceRangeAU) * Engine.kilometersPerAU > record.allowedErrorKm)
    }
}

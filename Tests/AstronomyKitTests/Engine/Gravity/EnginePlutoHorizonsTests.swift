//
//  EnginePlutoHorizonsTests.swift
//  AstronomyKit
//
//  The Swift Pluto against JPL Horizons: the public Pluto suites'
//  references and allowances, and Horizons vectors across the blends, the
//  integrated model's seams and the extrapolation beyond its table.
//

import Foundation
import Testing

@testable import AstronomyKit

extension PlutoSegmentSuites {
    @Suite("Engine Pluto against JPL Horizons")
    struct EnginePlutoHorizonsTests {
        typealias Pluto = Engine.Pluto

        /// The astrometric geocentric EQJ vector, Horizons' definition: Pluto at
        /// the time light left it, minus Earth at `time`, with no aberration,
        /// from the public Pluto route.
        static func geocentric(at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
            try CelestialBody.pluto.geocentricPosition(at: AstroTime(time), aberration: .none)
                .engineVector(in: Engine.EQJ.self)
        }

        static func heliocentric(at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
            try CelestialBody.pluto.heliocentricPosition(at: AstroTime(time)).engineVector(in: Engine.EQJ.self)
        }

        static func topocentric(from observer: Observer, at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
            let geocentric = try geocentric(at: time)
            let site = Engine.Observers.vector(observer, at: time)
            return Engine.Vector(
                x: geocentric.x - site.x, y: geocentric.y - site.y, z: geocentric.z - site.z, time: geocentric.time)
        }

        @Test("The JPLValidationTests geocentric Pluto suite within its 1′")
        func geocentric() throws {
            #expect(PlutoValidationTests.referenceData.count == 4)
            for reference in PlutoValidationTests.referenceData {
                let vector = try Self.geocentric(at: EnginePlanetHorizonsTests.time(reference))
                let arcminutes = try EnginePlanetHorizonsTests.separation(vector, reference)
                #expect(arcminutes <= toleranceArcminutes, "\(reference.month)-\(reference.day): \(arcminutes)′")
            }
        }

        @Test("The JPLValidationTests Asheville Pluto suite within its 1.5′")
        func asheville() throws {
            #expect(AshevilleValidationTests.plutoData.count == 4)
            for reference in AshevilleValidationTests.plutoData {
                let vector = try Self.topocentric(
                    from: ashevilleObserver, at: EnginePlanetHorizonsTests.time(reference))
                let arcminutes = try EnginePlanetHorizonsTests.separation(vector, reference)
                #expect(
                    arcminutes <= outerPlanetToleranceArcminutes, "\(reference.month)-\(reference.day): \(arcminutes)′")
            }
        }

        /// The `pluto-observer` rows at 1900, 2000 and 2100 that
        /// `AuditValidationTests.jplGeocentricObservation` reads, with its 1.5′.
        /// They are apparent positions, which differ from the astrometric ones
        /// by up to about 20″ of aberration.
        @Test("The ICRF direction and the ecliptic of date against the pluto-observer rows")
        func observerRows() throws {
            let rows = IndependentReferenceArchive.shared.observations.filter { $0.body == "pluto" }
            #expect(rows.count == 3)
            for row in rows {
                let ut = IndependentReferenceDate.civil(row.utc, deltaTModel: .espenakMeeus).universalTime
                let time = Engine.Time(ut: ut, deltaTModel: .espenakMeeus)
                let vector = try Self.geocentric(at: time)
                let equatorial = try Engine.Equatorial(vector)
                let arcminutes = IndependentReferenceMath.angularSeparationArcminutes(
                    raDegrees1: equatorial.rightAscension * 15, decDegrees1: equatorial.declination,
                    raDegrees2: row.rightAscensionDegrees, decDegrees2: row.declinationDegrees)
                #expect(arcminutes <= row.angularToleranceArcminutes, "\(row.utc): \(arcminutes)′")
                let ecliptic = Engine.Ecliptic(Engine.Vector(x: vector.x, y: vector.y, z: vector.z, time: time))
                let longitude = IndependentReferenceMath.wrappedDifference(
                    ecliptic.longitude, row.eclipticLongitudeDegrees)
                #expect(abs(longitude) * 60 <= row.angularToleranceArcminutes, "\(row.utc)")
                #expect(abs(ecliptic.latitude - row.eclipticLatitudeDegrees) * 60 <= row.angularToleranceArcminutes)
            }
        }

        /// The Pluto records of `distance-fixtures.json`: Horizons' heliocentric
        /// and light-time geocentric ranges from 1901 to 2100, with the
        /// allowances `DistanceAccuracyTests` applies to the public distance.
        @Test("Heliocentric and geocentric distances within the DistanceAccuracyTests allowances")
        func distances() throws {
            let records = DistanceReferenceArchive.shared.references.filter { $0.body == "Pluto" }
            #expect(records.count == 2 * 134)
            for reference in records {
                let time = Engine.Time(tt: reference.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
                let range =
                    reference.mode == "heliocentric"
                    ? try Self.heliocentric(at: time).length : try Self.geocentric(at: time).length
                let errorKm = abs(range - reference.observableRangeAU) * Engine.kilometersPerAU
                #expect(
                    errorKm <= reference.allowedErrorKm,
                    "\(reference.mode) JD TT \(reference.julianDateTT): \(errorKm) km, allowance \(reference.allowedErrorKm) km"
                )
            }
        }

        // MARK: - Horizons vectors

        /// `vector` against `reference`, a Horizons position on ICRF axes: the
        /// angle between them in arcminutes.
        static func arcminutes(
            _ vector: SIMD3<Double>, _ reference: IndependentReferenceArchive.Vector
        ) throws -> Double {
            let time = Engine.Time.invalid
            let engine = Engine.Vector<Engine.EQJ>(x: vector.x, y: vector.y, z: vector.z, time: time)
            let published = expected(reference)
            return try engine.angle(to: Engine.Vector(x: published.x, y: published.y, z: published.z, time: time)) * 60
        }

        /// The Horizons position rotated to EQJ.
        static func expected(_ reference: IndependentReferenceArchive.Vector) -> SIMD3<Double> {
            let icrs = reference.positionAU
            return Engine.FrameBias.icrsToEqj.apply(to: SIMD3(icrs[0], icrs[1], icrs[2]))
        }

        /// The TT of a Horizons epoch, which is in TDB.
        static func tt(_ reference: IndependentReferenceArchive.Vector) -> Double {
            let tdb = reference.julianDateTDB - 2_451_545
            return tdb - Engine.TDB.offsetSeconds(tt: tdb) / 86_400
        }

        /// The engine state retained for the DE441 representation tests that reuse this helper.
        static func state(_ reference: IndependentReferenceArchive.Vector) throws -> Engine.State<Engine.EQJ> {
            try Pluto.heliocentricState(at: PlanetTestSupport.time(tt: tt(reference)))
        }

        /// The public Pluto position and state at a Horizons epoch.
        static func publicState(_ reference: IndependentReferenceArchive.Vector) throws -> StateVector {
            let time = AstroTime(PlanetTestSupport.time(tt: tt(reference)))
            let position = try CelestialBody.pluto.heliocentricPosition(at: time)
            let state = try CelestialBody.pluto.heliocentricState(at: time)
            #expect(position == state.position)
            return state
        }

        static func length(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }
        static func position(_ state: StateVector) -> SIMD3<Double> {
            SIMD3(state.position.x, state.position.y, state.position.z)
        }
        static func velocity(_ state: StateVector) -> SIMD3<Double> {
            SIMD3(state.velocity.x, state.velocity.y, state.velocity.z)
        }

        /// Horizons' Pluto (999) from `sources/horizons/pluto-vector.json`: 29
        /// dates from 1840 to 2159.
        static let vectors = IndependentReferenceArchive.shared.vectors.filter { $0.body == "pluto" }

        /// The dates in the DE440 span, where Pluto is plu060's.
        static let de440 = vectors.filter { Engine.PlutoEphemeris.weight(tt: tt($0)).weight == 1 }

        /// Inside the DE440 span Pluto is the plu060 data Horizons also reads.
        /// The samples agree within 0.005″ and 0.05 km, and in velocity within
        /// 4e-10 of the speed; the bounds are 1 km and 1e-8.
        @Test("Public Pluto state in the DE440 span within 1 km and 1e-8 of the speed")
        func de440Vectors() throws {
            #expect(Self.vectors.count == 29)
            #expect(Self.de440.count == 29)
            for reference in Self.de440 {
                let state = try Self.publicState(reference)
                let km = Self.length(Self.position(state) - Self.expected(reference)) * Engine.kilometersPerAU
                #expect(km <= 1, "\(reference.tdb): \(km) km")
                let v = reference.velocityAUPerDay
                let velocity = Engine.FrameBias.icrsToEqj.apply(to: SIMD3(v[0], v[1], v[2]))
                let relative = Self.length(Self.velocity(state) - velocity) / Self.length(velocity)
                #expect(relative <= 1e-8, "\(reference.tdb): \(relative)")
            }
        }

        /// Every retained center direction now lies inside the expanded full-weight source span.
        @Test("All archived physical-center directions remain within 1′")
        func modelVectors() throws {
            #expect(Self.vectors.count == 29)
            for reference in Self.vectors {
                let arcminutes = try Self.arcminutes(Self.position(try Self.publicState(reference)), reference)
                #expect(arcminutes <= toleranceArcminutes, "\(reference.tdb): \(arcminutes)′")
            }
        }

        /// Horizons' Pluto system barycenter (9) from
        /// `sources/horizons/pluto-barycenter-vector.json`, where Horizons has no
        /// Pluto center: 15 dates from 100 BCE to 4098 CE. These references qualify barycenter directions; the full-range physical-center offset remains unqualified.
        static let barycenterVectors = IndependentReferenceArchive.shared.vectors.filter {
            $0.body == "pluto-barycenter"
        }

        /// The public DE441 route agrees with the archived system-barycenter directions; this does not certify full-range center motion.
        @Test(
            "Far from J2000 the public barycenter approximation meets 1′",
            arguments: barycenterVectors.map(\.julianDateTDB))
        func farFromJ2000(julianDateTDB: Double) throws {
            let reference = try #require(Self.barycenterVectors.first { $0.julianDateTDB == julianDateTDB })
            let arcminutes = try Self.arcminutes(Self.position(try Self.publicState(reference)), reference)
            #expect(arcminutes <= toleranceArcminutes, "\(reference.tdb): \(arcminutes)′")
        }

        @Test("The public checks fail a day off, and with the barycentric state")
        func negativeControls() throws {
            let reference = PlutoValidationTests.referenceData[0]
            let time = EnginePlanetHorizonsTests.time(reference)
            #expect(
                try EnginePlanetHorizonsTests.separation(Self.geocentric(at: time.adding(days: 1)), reference)
                    > toleranceArcminutes)
            let sample = try #require(Self.de440.first)
            let tt = Self.tt(sample)
            let dayOff = try CelestialBody.pluto.heliocentricState(at: AstroTime(PlanetTestSupport.time(tt: tt + 1)))
            #expect(Self.length(Self.position(dayOff) - Self.expected(sample)) * Engine.kilometersPerAU > 1)
            let barycentric = try CelestialBody.pluto.barycentricState(at: AstroTime(PlanetTestSupport.time(tt: tt)))
            #expect(Self.length(Self.position(barycentric) - Self.expected(sample)) * Engine.kilometersPerAU > 1)
        }
    }
}

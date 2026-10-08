//
//  ChironTests.swift
//  AstronomyKit
//
//  Tests for Chiron position calculations.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Chiron Tests")
struct ChironTests {
    // MARK: - Supported Range Tests

    @Suite("Supported Range")
    struct SupportedRange {
        @Test("Years outside 1900-2150 throw badTime", arguments: [1_800, 2_200])
        func outOfRangeThrows(year: Int) {
            let time = AstroTime(year: year, month: 1, day: 1)
            #expect(throws: AstronomyError.badTime) {
                _ = try Chiron.heliocentricPosition(at: time)
            }
        }

        @Test("Interior years succeed", arguments: [1_950, 2_100])
        func interiorYearsSucceed(year: Int) throws {
            let time = AstroTime(year: year, month: 1, day: 1)
            _ = try Chiron.heliocentricPosition(at: time)
        }

        static let earliestTT = AstroTime(ut: -36_524.5, deltaTModel: .espenakMeeus).terrestrialTime
        static let latestTT = AstroTime(year: 2_150, month: 1, day: 1).terrestrialTime

        @Test("The span ends at 1900-01-01 00:00 UT and 2150-01-01 00:00 UTC, as TT in the time's model")
        func spanEnds() throws {
            for model in DeltaTModel.allCases {
                let earliest = AstroTime(ut: -36_524.5, deltaTModel: model)
                try Chiron.checkSupported(earliest)
                try Chiron.checkSupported(AstroTime(tt: Self.latestTT, deltaTModel: model))
                #expect(throws: AstronomyError.badTime) {
                    try Chiron.checkSupported(AstroTime(tt: earliest.terrestrialTime.nextDown, deltaTModel: model))
                }
                // The C engine's Delta T has no drop at 1900-01-01, unlike the
                // engine's (EngineChironTests), so a UT just before is outside.
                #expect(throws: AstronomyError.badTime) {
                    try Chiron.checkSupported(AstroTime(ut: -36_524.5 - 0.001 / 86_400, deltaTModel: model))
                }
                #expect(throws: AstronomyError.badTime) {
                    try Chiron.checkSupported(AstroTime(tt: Self.latestTT.nextUp, deltaTModel: model))
                }
            }
        }

        /// A pair rebuilt from recorded scales need not agree with its model.
        /// The simulation steps in TT, so the span is checked on TT alone.
        @Test("A time is checked by its TT; its UT neither passes nor blocks it")
        func checkedByTerrestrialTime() throws {
            // 2000-01-01 UT with a TT 2,700 years earlier, then each end.
            let outside = [
                AstroTime(tt: -1_000_000, ut: 0),
                AstroTime(tt: Self.earliestTT.nextDown, ut: 0),
                AstroTime(tt: Self.latestTT.nextUp, ut: 0),
            ]
            for time in outside {
                #expect(throws: AstronomyError.badTime) { _ = try Chiron.heliocentricPosition(at: time) }
                #expect(throws: AstronomyError.badTime) { _ = try Chiron.geoState(at: time) }
            }
            try Chiron.checkSupported(AstroTime(tt: Self.earliestTT, ut: 0))
            try Chiron.checkSupported(AstroTime(tt: Self.latestTT, ut: 1_000_000))

            let pair = try Chiron.heliocentricPosition(at: AstroTime(tt: 0, ut: -1_000_000))
            let consistent = try Chiron.heliocentricPosition(at: AstroTime(tt: 0))
            #expect(abs(pair.x - consistent.x) < 1e-12)
            #expect(abs(pair.y - consistent.y) < 1e-12)
            #expect(abs(pair.z - consistent.z) < 1e-12)
        }
    }

    // MARK: - Basic Position Tests

    @Suite("Position Calculations")
    struct PositionTests {
        @Test("Heliocentric position returns valid vector")
        func heliocentricPositionValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let position = try Chiron.heliocentricPosition(at: time)

            // Chiron should be 8-18 AU from the Sun (it varies as a centaur)
            let distance = position.magnitude
            #expect(
                distance > 8.0 && distance < 20.0,
                "Chiron distance \(distance) AU should be between 8 and 20 AU"
            )
        }

        @Test("Geocentric position returns valid vector")
        func geocentricPositionValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let position = try Chiron.geocentricPosition(at: time)

            // Geocentric distance should be roughly heliocentric ± 1 AU
            let distance = position.magnitude
            #expect(
                distance > 7.0 && distance < 21.0,
                "Chiron geocentric distance \(distance) AU is reasonable"
            )
        }

        @Test("Equatorial coordinates are valid")
        func equatorialValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let eq = try Chiron.equatorial(at: time)

            #expect(
                eq.rightAscension >= 0 && eq.rightAscension < 24,
                "RA should be in [0, 24) hours"
            )
            #expect(eq.declination >= -90 && eq.declination <= 90, "Dec should be in [-90, 90]°")
            #expect(eq.distance > 0, "Distance should be positive")
        }

        @Test("Ecliptic longitude is in valid range")
        func eclipticLongitudeValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let longitude = try Chiron.eclipticLongitude(at: time)

            #expect(longitude >= 0 && longitude < 360, "Ecliptic longitude should be in [0, 360)°")
        }

        @Test("Ecliptic latitude is in valid range")
        func eclipticLatitudeValid() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let latitude = try Chiron.eclipticLatitude(at: time)

            // Chiron's orbit has ~7° inclination, so latitude should be modest
            #expect(
                latitude >= -15 && latitude <= 15,
                "Ecliptic latitude \(latitude)° should be reasonable"
            )
        }
    }

    // MARK: - Epoch Reference Tests

    @Suite("Reference Epoch Accuracy")
    struct EpochTests {
        static let anchors: [(year: Int, position: (Double, Double, Double))] = [
            (2_000, (-3.532082802845036, -8.673587566387649, -2.935491685233997)),
            (2_010, (13.19148992863117, -9.058771972133892, -2.018744306999665)),
            (2_020, (18.74979015626275, 0.9060856547258316, 1.445166327129911)),
            (2_030, (13.13185175469694, 10.45171373019759, 4.086005508618447)),
            (2_040, (-1.878330124332237, 10.99286850835428, 3.325776674355994)),
        ]

        @Test("Reference anchors remain exact", arguments: anchors)
        func referenceAnchorsRemainExact(anchor: (year: Int, position: (Double, Double, Double))) throws {
            let position = try Chiron.heliocentricPosition(
                at: AstroTime(year: anchor.year, month: 1, day: 1))

            #expect(abs(position.x - anchor.position.0) < 1e-12)
            #expect(abs(position.y - anchor.position.1) < 1e-12)
            #expect(abs(position.z - anchor.position.2) < 1e-12)
        }
    }

    // MARK: - Multi-Year Tests

    @Suite("Multi-Year Calculations")
    struct MultiYearTests {
        @Test("Positions over 10 years are consistent")
        func tenYearRange() throws {
            var lastLongitude: Double?

            // Check positions at start of each year from 2020-2030
            for year in 2_020...2_030 {
                let time = AstroTime(year: year, month: 1, day: 1)
                let longitude = try Chiron.eclipticLongitude(at: time)

                #expect(longitude >= 0 && longitude < 360, "Longitude valid for year \(year)")

                if let prev = lastLongitude {
                    // Chiron moves roughly 1-3° per year (50 year orbital period)
                    // Annual change should be modest
                    var delta = longitude - prev
                    if delta < -180 { delta += 360 }
                    if delta > 180 { delta -= 360 }

                    #expect(
                        abs(delta) < 20,
                        "Annual change \(delta)° at year \(year) is reasonable"
                    )
                }

                lastLongitude = longitude
            }
        }
    }

    // MARK: - Horizon Coordinates

    @Suite("Horizon Coordinates")
    struct HorizonTests {
        @Test("Horizon coordinates for observer are valid")
        func horizonValid() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21, hour: 12)
            let observer = Observer(latitude: 35.5, longitude: -82.5)  // Asheville, NC
            let horizon = try Chiron.horizon(at: time, from: observer)

            #expect(horizon.altitude >= -90 && horizon.altitude <= 90, "Altitude is valid")
            #expect(horizon.azimuth >= 0 && horizon.azimuth < 360, "Azimuth is valid")
        }

        /// Where `vector`, a geocentric J2000 direction, appears from
        /// `ashevilleObserver` at `time`, through the single J2000-to-horizon
        /// rotation (`Astronomy_Rotation_EQJ_HOR`) with no refraction. It
        /// composes the rotation to the true equator of date with the
        /// sidereal-time and observer rotations in one matrix, where
        /// `Chiron.horizon` rotates to the equator of date, converts to
        /// right ascension and declination, and calls `Astronomy_Horizon`.
        private static func horizontal(of vector: Vector3D, at time: AstroTime) throws -> Horizon {
            let rotation = try RotationMatrix.equatorialJ2000ToHorizon(at: time, from: ashevilleObserver)
            let spherical = Spherical.fromHorizonVector(try vector.rotated(by: rotation), refraction: .none)
            return Horizon(altitude: spherical.latitude, azimuth: spherical.longitude)
        }

        /// The angle between two horizon directions, in arcminutes. Azimuth
        /// differences shrink toward the zenith, so this compares directions
        /// rather than the two angles one by one.
        private static func separationArcminutes(_ lhs: Horizon, _ rhs: Horizon) -> Double {
            IndependentReferenceMath.angularSeparationArcminutes(
                raDegrees1: lhs.azimuth, decDegrees1: lhs.altitude,
                raDegrees2: rhs.azimuth, decDegrees2: rhs.altitude)
        }

        /// Precession moves the equator about 50.3 arcseconds a year, so J2000
        /// coordinates in the horizon conversion put Chiron 22′ off in 2026 and
        /// 84′ off in 2100 (#200); the 1e-9 degree bound is far below that.
        @Test(
            "Horizon is Chiron's position on the equator of date",
            arguments: [
                AstroTime(year: 2_026, month: 7, day: 1, hour: 3),
                AstroTime(year: 2_100, month: 1, day: 1, hour: 3),
            ])
        func horizonIsOnEquatorOfDate(time: AstroTime) throws {
            let position = try Chiron.geocentricPosition(at: time)
            let expected = try Self.horizontal(of: position, at: time)
            let horizon = try Chiron.horizon(at: time, from: ashevilleObserver, refraction: .none)

            // Both routes rotate one vector through the same frames, so they
            // differ by double-precision rounding, a few 1e-14 degrees. The
            // azimuth is scaled by the cosine of the altitude, as it shrinks
            // toward the zenith.
            let altitude = abs(horizon.altitude - expected.altitude)
            let azimuth = abs(IndependentReferenceMath.wrappedDifference(horizon.azimuth, expected.azimuth))
            #expect(altitude < 1e-9, "\(time): altitude \(altitude)°")
            #expect(azimuth * cos(expected.altitude * .pi / 180) < 1e-9, "\(time): azimuth \(azimuth)°")
        }

        /// Horizons' astrometric direction, which has no aberration as the API
        /// has none, is the published position. The 1′ row tolerance is the
        /// accuracy `Engine Chiron positions` measures against these rows;
        /// the largest difference here is 0.49′, in 1900.
        @Test("Horizon matches the Horizons observer rows rotated to the equator of date")
        func horizonMatchesHorizonsRows() throws {
            let rows = IndependentReferenceArchive.shared.chironObservations
            #expect(!rows.isEmpty)
            for row in rows {
                let time = IndependentReferenceDate.civil(row.utc)
                let vector = Vector3D.from(
                    sphere: Spherical(
                        latitude: row.declinationDegrees, longitude: row.rightAscensionDegrees, distance: 1),
                    at: time)
                let expected = try Self.horizontal(of: vector, at: time)
                let horizon = try Chiron.horizon(at: time, from: ashevilleObserver, refraction: .none)
                let separation = Self.separationArcminutes(horizon, expected)
                #expect(separation <= row.angularToleranceArcminutes, "\(row.utc): \(separation)′")
            }
        }
    }

    // MARK: - Epoch Continuity

    @Suite("Epoch Continuity")
    struct EpochContinuityTests {
        private func distance(_ a: Vector3D, _ b: Vector3D) -> Double {
            let dx = a.x - b.x
            let dy = a.y - b.y
            let dz = a.z - b.z
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }

        @Test("Position is not frozen near a reference epoch")
        func notFrozenNearEpoch() throws {
            // The state must be evaluated at the requested time, not returned
            // verbatim for any time within a day of a reference epoch.
            let epoch = AstroTime(year: 2_020, month: 1, day: 1)
            let nearby = epoch.addingHours(12)

            let posAtEpoch = try Chiron.heliocentricPosition(at: epoch)
            let posNearby = try Chiron.heliocentricPosition(at: nearby)

            // Chiron moves ~3e-3 AU/day, so half a day of motion is ~1.5e-3 AU.
            let moved = distance(posAtEpoch, posNearby)
            #expect(moved > 1e-4, "Position should move over 12 hours (moved \(moved) AU)")
            #expect(moved < 1e-2, "Position should not jump (moved \(moved) AU)")
        }

        @Test("Position is continuous across the one-day epoch boundary")
        func continuousAcrossBoundary() throws {
            let epoch = AstroTime(year: 2_020, month: 1, day: 1)
            let before = epoch.addingDays(0.9)
            let after = epoch.addingDays(1.1)

            let posBefore = try Chiron.heliocentricPosition(at: before)
            let posAfter = try Chiron.heliocentricPosition(at: after)

            // 0.2 days of orbital motion is ~6e-4 AU; a discontinuity at the
            // boundary would show up as a jump of a full day's motion or more.
            let moved = distance(posBefore, posAfter)
            #expect(moved > 1e-5, "Position should move across the boundary (moved \(moved) AU)")
            #expect(moved < 1.5e-3, "Position should not jump at the boundary (moved \(moved) AU)")
        }

        @Test("Position is continuous when the nearest reference anchor changes")
        func continuousAcrossReferenceTransition() throws {
            let before = AstroTime(year: 2_004, month: 12, day: 31, hour: 11, minute: 59)
            let after = AstroTime(year: 2_004, month: 12, day: 31, hour: 12, minute: 1)

            let posBefore = try Chiron.heliocentricPosition(at: before)
            let posAfter = try Chiron.heliocentricPosition(at: after)

            #expect(distance(posBefore, posAfter) < 0.01)
        }

        @Test("Returned state carries the requested time")
        func stateCarriesRequestedTime() throws {
            let epoch = AstroTime(year: 2_020, month: 1, day: 1)
            let nearby = epoch.addingHours(6)

            let state = try Chiron.geoState(at: nearby)

            #expect(abs(state.time.universalTime - nearby.universalTime) < 1e-9)
        }
    }

    // MARK: - State Vector Tests

    @Suite("State Vector")
    struct StateVectorTests {
        @Test("Geocentric state has valid velocity")
        func geoStateVelocity() throws {
            let time = AstroTime(year: 2_025, month: 1, day: 1)
            let state = try Chiron.geoState(at: time)

            // Velocity magnitude should be reasonable for a centaur
            let speed = state.velocity.magnitude
            #expect(speed > 0 && speed < 0.1, "Velocity \(speed) AU/day is reasonable")  // ~5 km/s max
        }
    }

    // MARK: - Simulation Reuse

    @Suite("Simulation Reuse")
    struct SimulationReuseTests {
        private func maximumComponentError(_ a: Vector3D, _ b: Vector3D) -> Double {
            max(abs(a.x - b.x), abs(a.y - b.y), abs(a.z - b.z))
        }

        @Test("A nearby reverse update reuses a long-span simulation without changing its result")
        func nearbyReverseUpdateMatchesFreshPropagation() throws {
            let reusable = Chiron.ReusableSimulation()
            _ = try reusable.state(at: AstroTime(year: 2_100, month: 1, day: 1))
            let target = AstroTime(year: 2_099, month: 12, day: 31, hour: 18)

            let reused = try reusable.state(at: target).position
            let fresh = try Chiron.heliocentricPosition(at: target)

            #expect(maximumComponentError(reused, fresh) < 1e-8)
        }

        @Test("A rejected time leaves the reuse state as it was")
        func rejectedKeepsReuseState() throws {
            let reusable = Chiron.ReusableSimulation()
            let start = AstroTime(year: 2_020, month: 4, day: 10)
            _ = try reusable.state(at: start)
            let path = reusable.pathDays
            #expect(throws: AstronomyError.badTime) {
                _ = try reusable.state(at: AstroTime(tt: -1_000_000, ut: start.universalTime))
            }
            #expect(reusable.epochIndex == 2 && reusable.pathDays == path)
            _ = try reusable.state(at: start.addingDays(-30))
            #expect(reusable.epochIndex == 2 && abs(reusable.pathDays - (path + 30)) < 1e-6)
        }

        @Test("Light-time correction remains physically bounded after long-span propagation")
        func longSpanLightTimeCorrection() throws {
            let position = try Chiron.geocentricPosition(
                at: AstroTime(year: 2_100, month: 1, day: 1))

            #expect(position.magnitude > 5)
            #expect(position.magnitude < 15)
        }
    }
}

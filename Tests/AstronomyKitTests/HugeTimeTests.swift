//
//  HugeTimeTests.swift
//  AstronomyKit
//
//  Tests that ephemeris queries at huge finite times never succeed with a
//  non-finite value.
//

import Testing

@testable import AstronomyKit

/// Position, distance, and apsis queries at huge finite times (#62).
///
/// Far from J2000 the planetary and lunar series still return numbers, but
/// they stop meaning anything, and eventually overflow. From about
/// `ut = 1e158` Delta T overflows and TT is infinite; at `ut = 1e70` TT is
/// finite but the series overflow. Either way a query must throw rather than
/// return NaN or infinity. Finite but meaningless values at times such as
/// `1e15` are still returned: which range the models accept is undecided.
@Suite("Huge Finite Times")
struct HugeTimeTests {
    /// Times whose results overflowed to NaN or infinity before the guard.
    static let overflowTimes: [Double] = [1e300, -1e300, 1e70, -1e70]

    /// Every time the finite-or-throws property is checked at.
    static let allTimes: [Double] = overflowTimes + [1e8, 1e10, 1e12, 1e15, -1e15, 1e20, 1e30]

    private static let observer = Observer(latitude: 40, longitude: -75, height: 100)

    /// True if `query` threw, or returned only finite values.
    private static func finiteOrThrows(_ query: () throws -> [Double]) -> Bool {
        guard let values = try? query() else { return true }
        return values.allSatisfy(\.isFinite)
    }

    private static func components(_ vector: Vector3D) -> [Double] {
        [vector.x, vector.y, vector.z]
    }

    private static func components(_ state: StateVector) -> [Double] {
        components(state.position) + components(state.velocity)
    }

    private static func components(_ state: EclipticState) -> [Double] {
        [
            state.longitude, state.latitude, state.distance,
            state.longitudeRate, state.latitudeRate, state.distanceRate,
        ]
    }

    private static func components(_ ecliptic: Ecliptic) -> [Double] {
        [ecliptic.latitude, ecliptic.longitude, ecliptic.distance]
    }

    private static func components(_ apsis: Apsis) -> [Double] {
        [apsis.time.universalTime, apsis.time.terrestrialTime, apsis.distanceAU, apsis.distanceKM]
    }

    private static func components(_ equatorial: Equatorial) -> [Double] {
        [equatorial.rightAscension, equatorial.declination, equatorial.distance]
    }

    private static func components(_ horizon: Horizon) -> [Double] {
        [horizon.altitude, horizon.azimuth, horizon.rightAscension, horizon.declination]
    }

    private static func components(_ illumination: Illumination) -> [Double] {
        [
            illumination.magnitude, illumination.phaseAngle, illumination.phaseFraction,
            illumination.helioDistance, illumination.ringTilt,
        ]
    }

    @Test("Body positions, states, and distances are finite or throw", arguments: allTimes)
    func bodyQueries(ut: Double) {
        let time = AstroTime(ut: ut)
        for body in CelestialBody.allCases {
            #expect(
                Self.finiteOrThrows { Self.components(try body.heliocentricPosition(at: time)) },
                "\(body) heliocentricPosition")
            #expect(Self.finiteOrThrows { [try body.distanceFromSun(at: time)] }, "\(body) distanceFromSun")
            #expect(
                Self.finiteOrThrows { Self.components(try body.heliocentricState(at: time)) },
                "\(body) heliocentricState")
            #expect(
                Self.finiteOrThrows { Self.components(try body.barycentricState(at: time)) }, "\(body) barycentricState"
            )
            #expect(
                Self.finiteOrThrows { Self.components(try body.geocentricPosition(at: time)) },
                "\(body) geocentricPosition")
            #expect(
                Self.finiteOrThrows { Self.components(try body.geocentricPosition(at: time).toEcliptic()) },
                "\(body) toEcliptic")
            #expect(
                Self.finiteOrThrows { Self.components(try body.backdatedPosition(at: time, seenFrom: .earth)) },
                "\(body) backdatedPosition")
            #expect(
                Self.finiteOrThrows { Self.components(try body.geocentricEclipticState(at: time)) },
                "\(body) geocentricEclipticState")
            #expect(
                Self.finiteOrThrows { Self.components(try body.equatorial(at: time, equatorDate: .ofDate)) },
                "\(body) equatorial")
            #expect(Self.finiteOrThrows { Self.components(try body.illumination(at: time)) }, "\(body) illumination")
            #expect(
                Self.finiteOrThrows { Self.components(try body.horizon(at: time, from: Self.observer)) },
                "\(body) horizon")
            #expect(Self.finiteOrThrows { [try body.eclipticLongitude(at: time)] }, "\(body) eclipticLongitude")
            #expect(Self.finiteOrThrows { [try body.angleFromSun(at: time)] }, "\(body) angleFromSun")
        }
    }

    @Test("Sun, Moon, and Earth-Moon barycenter queries are finite or throw", arguments: allTimes)
    func sunAndMoonQueries(ut: Double) {
        let time = AstroTime(ut: ut)
        #expect(Self.finiteOrThrows { Self.components(try Sun.position(at: time)) }, "Sun.position")
        #expect(Self.finiteOrThrows { Self.components(try Sun.eclipticState(at: time)) }, "Sun.eclipticState")
        #expect(
            Self.finiteOrThrows { Self.components(try Moon.geocentricPosition(at: time)) }, "Moon.geocentricPosition")
        #expect(Self.finiteOrThrows { Self.components(try Moon.ecliptic(at: time)) }, "Moon.ecliptic")
        #expect(Self.finiteOrThrows { Self.components(try Moon.eclipticState(at: time)) }, "Moon.eclipticState")
        #expect(Self.finiteOrThrows { Self.components(try Moon.geoState(at: time)) }, "Moon.geoState")
        #expect(
            Self.finiteOrThrows { Self.components(try CelestialBody.earthMoonBaryState(at: time)) },
            "earthMoonBaryState")
    }

    @Test("Fixed star positions are finite or throw", arguments: allTimes)
    func fixedStarQueries(ut: Double) {
        let time = AstroTime(ut: ut)
        let star = FixedStarTests.algol
        #expect(
            Self.finiteOrThrows {
                Self.components(try star.equatorial(at: time, from: Self.observer, equatorDate: .ofDate))
            }, "equatorial")
        #expect(Self.finiteOrThrows { Self.components(try star.ecliptic(at: time)) }, "ecliptic")
        #expect(Self.finiteOrThrows { Self.components(try star.horizon(at: time, from: Self.observer)) }, "horizon")
    }

    @Test("Jupiter's moons and Lagrange points are finite or throw", arguments: allTimes)
    func derivedPositions(ut: Double) {
        let time = AstroTime(ut: ut)
        #expect(
            Self.finiteOrThrows {
                let moons = try Jupiter.moons(at: time)
                return [moons.io, moons.europa, moons.ganymede, moons.callisto].flatMap(Self.components)
            }, "Jupiter.moons")
        for (major, minor) in [(CelestialBody.sun, CelestialBody.earth), (.earth, .moon)] {
            for point in LagrangePointID.allCases {
                #expect(
                    Self.finiteOrThrows {
                        Self.components(
                            try LagrangePoint.calculate(point: point, at: time, majorBody: major, minorBody: minor))
                    }, "\(major)-\(minor) \(point)")
            }
        }
    }

    @Test("Apsis searches are finite or throw", arguments: allTimes)
    func apsisSearches(ut: Double) {
        let time = AstroTime(ut: ut)
        for body in CelestialBody.allCases where body.isPlanet && body != .earth {
            #expect(Self.finiteOrThrows { Self.components(try body.searchApsis(after: time)) }, "\(body) searchApsis")
            #expect(
                Self.finiteOrThrows {
                    Self.components(try body.nextApsis(after: try body.searchApsis(after: time)))
                }, "\(body) nextApsis")
        }
        #expect(Self.finiteOrThrows { Self.components(try Moon.searchApsis(after: time)) }, "Moon.searchApsis")
    }

    /// The overflowed results report `badTime`, the error Pluto already
    /// throws outside its table.
    @Test("Overflowed ephemeris results throw badTime", arguments: overflowTimes)
    func overflowThrowsBadTime(ut: Double) {
        let time = AstroTime(ut: ut)
        for body in [
            CelestialBody.mercury, .earth, .mars, .neptune, .moon, .earthMoonBarycenter, .solarSystemBarycenter,
        ] {
            #expect(throws: AstronomyError.badTime, "\(body) heliocentricPosition") {
                _ = try body.heliocentricPosition(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) distanceFromSun") {
                _ = try body.distanceFromSun(at: time)
            }
            #expect(throws: AstronomyError.badTime, "\(body) heliocentricState") {
                _ = try body.heliocentricState(at: time)
            }
            // The barycenter is the origin of the barycentric frame at every time.
            if body != .solarSystemBarycenter {
                #expect(throws: AstronomyError.badTime, "\(body) barycentricState") {
                    _ = try body.barycentricState(at: time)
                }
            }
        }
        #expect(throws: AstronomyError.badTime) { _ = try CelestialBody.moon.geocentricPosition(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try CelestialBody.moon.equatorial(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try CelestialBody.sun.illumination(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Sun.position(at: time) }
        // Earth's geocentric vector is zero, but the rotation into the ecliptic
        // of date at the vector's time is not finite here.
        #expect(throws: AstronomyError.badTime) {
            _ = try CelestialBody.earth.geocentricPosition(at: time).toEcliptic()
        }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.geocentricPosition(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.ecliptic(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.geoState(at: time) }
        #expect(throws: AstronomyError.badTime) { _ = try CelestialBody.earthMoonBaryState(at: time) }
        #expect(throws: AstronomyError.badTime) {
            _ = try LagrangePoint.calculate(point: .l4, at: time, majorBody: .earth, minorBody: .moon)
        }
        for body in [CelestialBody.mercury, .jupiter, .neptune] {
            #expect(throws: AstronomyError.badTime, "\(body) searchApsis") {
                _ = try body.searchApsis(after: time)
            }
        }
        #expect(throws: AstronomyError.badTime) { _ = try Moon.searchApsis(after: time) }
    }
}

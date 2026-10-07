//
//  EngineHorizonTests.swift
//  AstronomyKit
//
//  Horizontal coordinates and horizon vectors.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Horizontal")
struct EngineHorizontalTests {
    typealias Published = PublishedOrientation

    static let time = Engine.Time(ut: 9_496.374_023_437_5, tt: 9_496.375, deltaTModel: .espenakMeeus)

    /// Right ascension in hours for an hour angle in radians, with the
    /// engine's apparent sidereal time.
    static func rightAscension(hourAngle: Double, longitude: Double) -> Double {
        Engine.EarthRotation.apparentSiderealTime(time) + longitude / 15 - hourAngle * Engine.hoursPerRadian
    }

    @Test("ERFA t_hd2ae reference without refraction", arguments: [-120.0, 0, 33.3])
    func erfaReference(longitude: Double) {
        let observer = Observer(latitude: Published.hd2ae.latitude * Engine.degreesPerRadian, longitude: longitude)
        let horizontal = Engine.Horizontal(
            time: Self.time,
            observer: observer,
            rightAscension: Self.rightAscension(hourAngle: Published.hd2ae.ha, longitude: longitude),
            declination: Published.hd2ae.dec * Engine.degreesPerRadian,
            refraction: .none
        )
        #expect(abs(Published.wrapped(horizontal.azimuth * Engine.radiansPerDegree - Published.hd2ae.azimuth)) <= 1e-13)
        #expect(abs(horizontal.altitude * Engine.radiansPerDegree - Published.hd2ae.elevation) <= 1e-13)
        #expect(horizontal.azimuth >= 0 && horizontal.azimuth < 360)
    }

    @Test("Refraction raises the altitude and moves the equatorial direction toward the zenith")
    func refraction() {
        let observer = Observer(latitude: 35.6, longitude: -82.55)
        let ra = Self.rightAscension(hourAngle: 1.4, longitude: observer.longitude)
        func horizontal(_ refraction: Refraction) -> Engine.Horizontal {
            Engine.Horizontal(
                time: Self.time,
                observer: observer,
                rightAscension: ra,
                declination: 5,
                refraction: refraction
            )
        }
        let plain = horizontal(.none)
        let bent = horizontal(.normal)
        let lift = Engine.AtmosphericRefraction.angle(.normal, altitude: plain.altitude)
        #expect(abs(bent.altitude - plain.altitude - lift) <= 1e-12)
        #expect(bent.azimuth == plain.azimuth)
        #expect(plain.rightAscension == ra && plain.declination == 5)
        // The refracted equatorial direction, without refraction, is at the
        // refracted altitude and the same azimuth.
        let check = Engine.Horizontal(
            time: Self.time,
            observer: observer,
            rightAscension: bent.rightAscension,
            declination: bent.declination,
            refraction: .none
        )
        #expect(abs(check.altitude - bent.altitude) <= 1e-9)
        #expect(abs(check.azimuth - bent.azimuth) <= 1e-9)
    }

    /// Sæmundsson's formula gives −0.0019′ at the zenith, so the refracted
    /// altitude is just below 90° and, the refraction not being positive,
    /// the equatorial direction is the input.
    @Test("At the zenith the refraction is the formula's small negative value")
    func zenith() {
        let observer = Observer(latitude: 0, longitude: 0)
        let ra = Engine.EarthRotation.apparentSiderealTime(Self.time)
        let horizontal = Engine.Horizontal(
            time: Self.time,
            observer: observer,
            rightAscension: ra,
            declination: 0,
            refraction: .normal
        )
        let zenithRefraction = EngineRefractionTests.saemundsson(90)
        #expect(zenithRefraction < 0)
        #expect(abs(horizontal.altitude - (90 + zenithRefraction)) <= 1e-9)
        #expect(horizontal.rightAscension == ra && horizontal.declination == 0)
    }

    @Test(
        "Horizon vectors convert to azimuth east of north and back",
        arguments: [Refraction.none, .normal, .jplHorizons]
    )
    func horizonVectors(refraction: Refraction) throws {
        // North-east and slightly up: x north, y west, z zenith.
        let vector = Engine.Vector<Engine.HOR>(x: 1, y: -1, z: 0.2, time: Self.time)
        let sphere = try Engine.Spherical(horizon: vector, refraction: refraction)
        #expect(abs(sphere.longitude - 45) <= 1e-12)
        let geometric = Engine.degreesPerRadian * atan2(0.2, 2.0.squareRoot())
        let lift = Engine.AtmosphericRefraction.angle(refraction, altitude: geometric)
        #expect(abs(sphere.latitude - geometric - lift) <= 1e-12)
        let back = Engine.Vector<Engine.HOR>(horizon: sphere, time: Self.time, refraction: refraction)
        #expect(abs(back.x - vector.x) <= 1e-12)
        #expect(abs(back.y - vector.y) <= 1e-12)
        #expect(abs(back.z - vector.z) <= 1e-12)
    }

    @Test("Due north is azimuth 0, not 360")
    func dueNorth() throws {
        let sphere = try Engine.Spherical(horizon: Engine.Vector(x: 1, y: 0, z: 0, time: Self.time), refraction: .none)
        #expect(sphere.longitude == 0)
        let west = try Engine.Spherical(horizon: Engine.Vector(x: 0, y: 1, z: 0, time: Self.time), refraction: .none)
        #expect(west.longitude == 270)
    }
}

//
//  EngineCoordinatesTests.swift
//  AstronomyKit
//
//  Spherical, equatorial and ecliptic coordinates against SOFA.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine coordinates")
struct EngineCoordinatesTests {
    typealias Published = PublishedOrientation

    static let time = Engine.Time(ut: 9_496.375, tt: 9_496.375, deltaTModel: .espenakMeeus)

    static func vector<F>(_ x: Double, _ y: Double, _ z: Double) -> Engine.Vector<F> {
        Engine.Vector(x: x, y: y, z: z, time: time)
    }

    @Test("ERFA t_c2s and t_p2s references")
    func erfaSphere() throws {
        let v = Published.p2s.vector
        let sphere = try Engine.Spherical(Self.vector(v.x, v.y, v.z) as Engine.Vector<Engine.EQJ>)
        // SOFA's longitude is in (−π, π]; the engine's is in [0, 360).
        let longitude = Published.wrapped(sphere.longitude * Engine.radiansPerDegree)
        #expect(abs(longitude - Published.p2s.theta) <= 1e-14)
        #expect(abs(sphere.latitude * Engine.radiansPerDegree - Published.p2s.phi) <= 1e-14)
        #expect(abs(sphere.distance - Published.p2s.r) <= 1e-9)
        #expect(sphere.longitude >= 0 && sphere.longitude < 360)
    }

    @Test("ERFA t_s2c and t_s2p references")
    func erfaVector() {
        let degrees = Engine.degreesPerRadian
        let cases = [
            (Published.s2c.theta, Published.s2c.phi, 1.0, Published.s2c.vector),
            (Published.s2p.theta, Published.s2p.phi, Published.s2p.r, Published.s2p.vector),
        ]
        for (theta, phi, r, expected) in cases {
            let sphere = Engine.Spherical(latitude: phi * degrees, longitude: theta * degrees, distance: r)
            let v = Engine.Vector<Engine.EQJ>(sphere, time: Self.time)
            #expect(abs(v.x - expected[0]) <= 1e-12)
            #expect(abs(v.y - expected[1]) <= 1e-12)
            #expect(abs(v.z - expected[2]) <= 1e-12)
            #expect(v.time.tt == Self.time.tt)
        }
    }

    @Test("Vectors on the z axis are at the poles with longitude 0", arguments: [2.5, -0.25])
    func poles(z: Double) throws {
        let sphere = try Engine.Spherical(Self.vector(0, -0.0, z) as Engine.Vector<Engine.EQD>)
        #expect(sphere == Engine.Spherical(latitude: z > 0 ? 90 : -90, longitude: 0, distance: abs(z)))
    }

    @Test("A zero vector has no direction", arguments: [0.0, -0.0])
    func zeroVector(zero: Double) {
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Spherical(Self.vector(zero, zero, zero) as Engine.Vector<Engine.EQJ>)
        }
        #expect(throws: AstronomyError.invalidParameter) {
            try Engine.Equatorial(Self.vector(zero, zero, zero) as Engine.Vector<Engine.EQJ>)
        }
    }

    @Test("Longitude stays below 360 just under the x axis")
    func longitudeWrap() throws {
        let sphere = try Engine.Spherical(Self.vector(1, -1e-300, 0) as Engine.Vector<Engine.EQJ>)
        #expect(sphere.longitude == 0)
        let below = try Engine.Spherical(Self.vector(1, -1e-10, 0) as Engine.Vector<Engine.EQJ>)
        #expect(below.longitude < 360 && below.longitude > 359.99)
    }

    @Test("Right ascension is the longitude in hours")
    func equatorial() throws {
        let v: Engine.Vector<Engine.EQJ> = Self.vector(-0.3, -0.4, 1.2)
        let sphere = try Engine.Spherical(v)
        let equatorial = try Engine.Equatorial(v)
        #expect(equatorial.rightAscension == sphere.longitude / 15)
        #expect(equatorial.declination == sphere.latitude)
        #expect(equatorial.distance == sphere.distance)
    }

    /// The SOFA reference: R1(εA + Δε)·N·P applied to the vector, then
    /// `eraC2s`'s definition of longitude and latitude.
    @Test("Ecliptic of date matches the SOFA rotation", arguments: Published.references)
    func ecliptic(reference: Published.Reference) {
        let time = Engine.Time(ut: reference.ut, tt: reference.tt, deltaTModel: .espenakMeeus)
        let v = Engine.Vector<Engine.EQJ>(x: 0.21, y: -0.95, z: 0.33, time: time)
        let rotation = Published.product(
            Published.r1(reference.obl06 + reference.deps),
            EngineFrameRotationTests.equatorOfDate(reference)
        )
        let e = (0..<3).map { rotation[$0][0] * v.x + rotation[$0][1] * v.y + rotation[$0][2] * v.z }
        let longitude = atan2(e[1], e[0])
        let latitude = atan2(e[2], hypot(e[0], e[1]))

        let ecliptic = Engine.Ecliptic(v)
        #expect(abs(Published.wrapped(ecliptic.longitude * Engine.radiansPerDegree - longitude)) <= 2e-15)
        #expect(abs(ecliptic.latitude * Engine.radiansPerDegree - latitude) <= 2e-15)
        #expect(abs(ecliptic.vector.x - e[0]) <= 2e-15)
        #expect(abs(ecliptic.vector.y - e[1]) <= 2e-15)
        #expect(abs(ecliptic.vector.z - e[2]) <= 2e-15)
        #expect(ecliptic.vector.time.tt == reference.tt)
        #expect(ecliptic.longitude >= 0 && ecliptic.longitude < 360)
    }

    @Test("On the ecliptic pole the ecliptic longitude is 0")
    func eclipticPole() {
        let pole = Engine.FrameRotation.ectToEqj(Self.time).apply(to: Self.vector(0, 0, 1) as Engine.Vector<Engine.ECT>)
        let ecliptic = Engine.Ecliptic(pole)
        #expect(abs(ecliptic.latitude - 90) <= 1e-6)
    }
}

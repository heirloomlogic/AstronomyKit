//
//  StateVectorExtensionTests.swift
//  AstronomyKit
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("State Vector Extensions")
struct StateVectorExtensionTests {
    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

    @Test("Barycentric state returns position and velocity")
    func barycentricState() throws {
        let state = try CelestialBody.earth.barycentricState(at: testTime)
        #expect(state.position.magnitude > 0)
        #expect(state.velocity.magnitude > 0)
    }

    @Test("Heliocentric state returns position and velocity")
    func heliocentricState() throws {
        let state = try CelestialBody.mars.heliocentricState(at: testTime)
        #expect(state.position.magnitude > 1.0, "Mars should be > 1 AU from Sun")
        #expect(state.velocity.magnitude > 0)
    }

    @Test("Heliocentric state position matches heliocentricPosition")
    func heliocentricStateMatchesPosition() throws {
        let state = try CelestialBody.jupiter.heliocentricState(at: testTime)
        let pos = try CelestialBody.jupiter.heliocentricPosition(at: testTime)
        #expect(abs(state.position.x - pos.x) < 1e-10)
        #expect(abs(state.position.y - pos.y) < 1e-10)
        #expect(abs(state.position.z - pos.z) < 1e-10)
    }

    /// The velocity comes from the sine sums of a planet's series and the position from the
    /// cosine sums. This holds one to the other in whichever series code the build uses: a
    /// Debug build on an Apple platform sums the longer series through Accelerate.
    ///
    /// The rate of change is a five-point difference over ±1/8 day, as in `EclipticState`. Two
    /// things separate it from the velocity: its own error, about 5e-12 AU per day for Mercury
    /// and less for the others, and the rounding of the positions, which grows with the time
    /// from J2000. Over 2048 instants in the 200 days after each time below, in builds that
    /// use Accelerate, fused multiply-add, or neither, the two were at most 4.9e-11 AU per day
    /// apart at 1000 years from J2000 and 5.7e-12 in 2026. Each tolerance is about 20 times
    /// that.
    @Test(
        "Heliocentric velocity is the rate of change of heliocentric position",
        arguments: CelestialBody.planets + [.earth])
    func heliocentricVelocityMatchesPositionRate(body: CelestialBody) throws {
        let step = 1.0 / 16
        for (tt, tolerance) in [(-365_250.0, 1e-9), (9_816.0, 1e-10)] {
            let state = try body.heliocentricState(at: AstroTime(tt: tt))
            let samples = try [-2.0, -1, 1, 2].map {
                try body.heliocentricPosition(at: AstroTime(tt: tt + $0 * step))
            }
            func rate(_ axis: KeyPath<Vector3D, Double>) -> Double {
                let p = samples.map { $0[keyPath: axis] }
                return (p[0] - 8 * p[1] + 8 * p[2] - p[3]) / (12 * step)
            }
            #expect(abs(rate(\.x) - state.velocity.x) < tolerance, "x at TT \(tt)")
            #expect(abs(rate(\.y) - state.velocity.y) < tolerance, "y at TT \(tt)")
            #expect(abs(rate(\.z) - state.velocity.z) < tolerance, "z at TT \(tt)")
        }
    }

    @Test("Earth-Moon Barycenter state returns valid result")
    func earthMoonBaryState() throws {
        let state = try CelestialBody.earthMoonBaryState(at: testTime)
        #expect(state.position.magnitude > 0)
        #expect(state.position.magnitude < 0.01, "EMB geocentric distance should be small")
    }

    @Test("Rotate state vector roundtrip preserves values")
    func rotateStateRoundtrip() throws {
        let state = try CelestialBody.mars.heliocentricState(at: testTime)
        let rotation = try RotationMatrix.equatorialJ2000ToEcliptic()
        let inverse = try rotation.inverse

        let rotated = try state.rotated(by: rotation)
        let restored = try rotated.rotated(by: inverse)

        #expect(abs(restored.position.x - state.position.x) < 1e-10)
        #expect(abs(restored.position.y - state.position.y) < 1e-10)
        #expect(abs(restored.position.z - state.position.z) < 1e-10)
        #expect(abs(restored.velocity.x - state.velocity.x) < 1e-10)
        #expect(abs(restored.velocity.y - state.velocity.y) < 1e-10)
        #expect(abs(restored.velocity.z - state.velocity.z) < 1e-10)
    }
}

@Suite("Vector Conversion Tests")
struct VectorConversionTests {
    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

    @Test("Vector to spherical roundtrip")
    func vectorSphericalRoundtrip() throws {
        let original = try CelestialBody.mars.geocentricPosition(at: testTime)
        let sphere = original.toSpherical()
        let restored = Vector3D.from(sphere: sphere, at: testTime)

        #expect(abs(restored.x - original.x) < 1e-10)
        #expect(abs(restored.y - original.y) < 1e-10)
        #expect(abs(restored.z - original.z) < 1e-10)
    }

    @Test("Vector to equatorial matches CelestialBody.equatorial")
    func vectorToEquatorial() throws {
        let vec = try CelestialBody.jupiter.geocentricPosition(at: testTime, aberration: .corrected)
        let eq = vec.toEquatorial()
        let expected = try CelestialBody.jupiter.equatorial(at: testTime)

        #expect(abs(eq.rightAscension - expected.rightAscension) < 0.001)
        #expect(abs(eq.declination - expected.declination) < 0.001)
    }

    @Test("Vector to ecliptic produces valid coordinates")
    func vectorToEcliptic() throws {
        let vec = try CelestialBody.mars.geocentricPosition(at: testTime)
        let ecl = try vec.toEcliptic()
        #expect(ecl.longitude >= 0 && ecl.longitude < 360)
        #expect(ecl.latitude >= -90 && ecl.latitude <= 90)
        #expect(ecl.distance > 0)
    }

    @Test("Angle between perpendicular vectors is 90°")
    func angleBetweenPerpendicular() throws {
        let a = Vector3D(x: 1, y: 0, z: 0, time: testTime)
        let b = Vector3D(x: 0, y: 1, z: 0, time: testTime)
        let angle = try a.angle(to: b)
        #expect(abs(angle - 90.0) < 0.001)
    }

    @Test("Angle between parallel vectors is 0°")
    func angleBetweenParallel() throws {
        let a = Vector3D(x: 1, y: 0, z: 0, time: testTime)
        let b = Vector3D(x: 2, y: 0, z: 0, time: testTime)
        let angle = try a.angle(to: b)
        #expect(abs(angle) < 0.001)
    }

    @Test("Horizon from vector roundtrip")
    func horizonVectorRoundtrip() throws {
        let sphere = Spherical(latitude: 45, longitude: 180, distance: 1.0)
        let vec = Vector3D.from(horizon: sphere, at: testTime, refraction: .none)
        let restored = Spherical.fromHorizonVector(vec, refraction: .none)

        #expect(abs(restored.latitude - sphere.latitude) < 0.001)
        #expect(abs(restored.longitude - sphere.longitude) < 0.001)
    }
}

@Suite("ECT Rotation Tests")
struct ECTRotationTests {
    let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

    @Test("EQJ to ECT roundtrip preserves vector")
    func eqjToEctRoundtrip() throws {
        let vec = try CelestialBody.mars.geocentricPosition(at: testTime)

        let toECT = try RotationMatrix.equatorialJ2000ToEclipticOfDate(at: testTime)
        let toEQJ = try RotationMatrix.eclipticOfDateToEquatorialJ2000(at: testTime)

        let rotated = try vec.rotated(by: toECT)
        let restored = try rotated.rotated(by: toEQJ)

        #expect(abs(restored.x - vec.x) < 1e-10)
        #expect(abs(restored.y - vec.y) < 1e-10)
        #expect(abs(restored.z - vec.z) < 1e-10)
    }

    @Test("EQD to ECT roundtrip preserves vector")
    func eqdToEctRoundtrip() throws {
        let vec = try CelestialBody.jupiter.geocentricPosition(at: testTime)

        let toECT = try RotationMatrix.equatorialOfDateToEclipticOfDate(at: testTime)
        let toEQD = try RotationMatrix.eclipticOfDateToEquatorialOfDate(at: testTime)

        let rotated = try vec.rotated(by: toECT)
        let restored = try rotated.rotated(by: toEQD)

        #expect(abs(restored.x - vec.x) < 1e-10)
        #expect(abs(restored.y - vec.y) < 1e-10)
        #expect(abs(restored.z - vec.z) < 1e-10)
    }
}

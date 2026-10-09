import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native coordinate facades")
struct NativeCoordinateFacadeTests {
    typealias Published = PublishedOrientation

    static func matrix(_ rotation: RotationMatrix) -> [[Double]] {
        (0..<3).map { row in (0..<3).map { rotation[$0, row] } }
    }

    @Test("Public frame rotations retain SOFA angle accuracy", arguments: Published.references)
    func frames(reference: Published.Reference) throws {
        let time = AstroTime(tt: reference.tt, ut: reference.ut, deltaTModel: .jplHorizons)
        let equator = EngineFrameRotationTests.equatorOfDate(reference)
        let tilt = Published.r1(reference.obl06 + reference.deps)
        let ecliptic = Published.product(tilt, equator)
        let mean = Published.r1(Published.p06e.eps0)
        let equatorToMean = Published.product(mean, Published.transposed(equator))
        let checks: [(RotationMatrix, [[Double]])] = [
            (try .equatorialJ2000ToEquatorialOfDate(at: time), equator),
            (try .equatorialOfDateToEquatorialJ2000(at: time), Published.transposed(equator)),
            (try .equatorialJ2000ToEclipticOfDate(at: time), ecliptic),
            (try .eclipticOfDateToEquatorialJ2000(at: time), Published.transposed(ecliptic)),
            (try .equatorialOfDateToEclipticOfDate(at: time), tilt),
            (try .eclipticOfDateToEquatorialOfDate(at: time), Published.transposed(tilt)),
            (try .equatorialOfDateToEcliptic(at: time), equatorToMean),
            (try .eclipticToEquatorialOfDate(at: time), Published.transposed(equatorToMean)),
            (try .equatorialJ2000ToEcliptic(), mean),
            (try .eclipticToEquatorialJ2000(), Published.transposed(mean)),
        ]
        for (rotation, expected) in checks {
            #expect(Published.maximumDifference(Self.matrix(rotation), expected) <= 2e-15)
        }
    }

    @Test("Public horizon rotations use the qualified sidereal orientation", arguments: Published.references)
    func horizon(reference: Published.Reference) throws {
        let time = AstroTime(tt: reference.tt, ut: reference.ut, deltaTModel: .jplHorizons)
        let nativeTime = Engine.Time(ut: reference.ut, tt: reference.tt, deltaTModel: .jplHorizons)
        let observer = Observer(latitude: 35.6, longitude: -82.55, height: 650)
        let expected = Published.matrix(Engine.FrameRotation.eqdToHor(nativeTime, observer: observer))
        let eqj = Published.product(expected, EngineFrameRotationTests.equatorOfDate(reference))
        let ecl = Published.product(eqj, Published.r1(-Published.p06e.eps0))
        let checks: [(RotationMatrix, [[Double]])] = [
            (try .equatorialOfDateToHorizon(at: time, from: observer), expected),
            (try .horizonToEquatorialOfDate(at: time, from: observer), Published.transposed(expected)),
            (try .equatorialJ2000ToHorizon(at: time, from: observer), eqj),
            (try .horizonToEquatorialJ2000(at: time, from: observer), Published.transposed(eqj)),
            (try .eclipticToHorizon(at: time, from: observer), ecl),
            (try .horizonToEcliptic(at: time, from: observer), Published.transposed(ecl)),
        ]
        for (rotation, expected) in checks {
            #expect(Published.maximumDifference(Self.matrix(rotation), expected) <= 2e-15)
        }
    }

    @Test("Public observer positions retain SOFA geodetic accuracy", arguments: EngineObserverTests.geodetic.indices)
    func observer(index: Int) throws {
        let c = EngineObserverTests.geodetic[index]
        let t = EngineObserverTests.time
        let time = AstroTime(tt: t.tt, ut: t.ut, deltaTModel: .jplHorizons)
        let observer = Observer(latitude: c.latitude, longitude: c.longitude, height: c.height)
        let vector = try observer.vector(at: time, equator: .ofDate)
        let native = Engine.Vector<Engine.EQD>(x: vector.x, y: vector.y, z: vector.z, time: t)
        let fixed = EngineObserverTests.earthFixed(native)
        for axis in 0..<3 {
            #expect(abs(fixed[axis] - c.xyz[axis]) <= 1e-6)
        }
        for frame in [EquatorDate.j2000, .ofDate] {
            let position = try observer.vector(at: time, equator: frame)
            let state = try observer.state(at: time, equator: frame)
            #expect(state.position == position)
            #expect(state.time.terrestrialTime == time.terrestrialTime)
            #expect(state.time.deltaTModel == .jplHorizons)
            #expect(state.velocity.time.terrestrialTime == time.terrestrialTime)
            let back = Observer.from(vector: position, equatorDate: frame)
            #expect(abs(back.latitude - c.latitude) <= 1e-8)
            #expect(abs(back.height - c.height) <= 1e-3)
        }
    }

    @Test("Body and star horizontal conversions use the public native rotation")
    func horizontalConsumers() throws {
        let time = AstroTime(ut: 9_496.375, deltaTModel: .jplHorizons)
        let observer = Observer(latitude: 35.6, longitude: -82.55, height: 650)
        let star = FixedStar(name: "Geometry", rightAscension: 3.1, declination: 40.9, distance: 93)
        var cases: [(Equatorial, Horizon)] = []
        for body in [CelestialBody.mercury, .mars, .moon] {
            cases.append(
                (
                    try body.equatorial(at: time, from: observer, equatorDate: .ofDate),
                    try body.horizon(at: time, from: observer, refraction: .none)
                ))
        }
        cases.append(
            (
                try star.equatorial(at: time, from: observer, equatorDate: .ofDate),
                try star.horizon(at: time, from: observer, refraction: .none)
            ))
        let rotation = try RotationMatrix.equatorialOfDateToHorizon(at: time, from: observer)
        for (equatorial, actual) in cases {
            let vector = Vector3D.from(
                sphere: Spherical(
                    latitude: equatorial.declination, longitude: equatorial.rightAscension * 15, distance: 1),
                at: time)
            let expected = Spherical.fromHorizonVector(try vector.rotated(by: rotation), refraction: .none)
            #expect(abs(actual.altitude - expected.latitude) <= 1e-12)
            #expect(abs(actual.azimuth - expected.longitude) <= 1e-12)
            #expect(actual.rightAscension == equatorial.rightAscension)
            #expect(actual.declination == equatorial.declination)
        }
    }

    @Test("Nonthrowing zero-vector conversions keep NaN fields and input epoch")
    func zeroConversions() {
        let time = AstroTime(tt: 4, ut: 2, deltaTModel: .jplHorizons)
        let zero = Vector3D(x: 0, y: -0.0, z: 0, time: time)
        let sphere = zero.toSpherical()
        #expect(sphere.latitude.isNaN && sphere.longitude.isNaN && sphere.distance.isNaN)
        let equator = zero.toEquatorial()
        #expect(equator.rightAscension.isNaN && equator.declination.isNaN && equator.distance.isNaN)
        #expect(equator.time.terrestrialTime == 4 && equator.time.deltaTModel == .jplHorizons)
        let horizon = Spherical.fromHorizonVector(zero)
        #expect(horizon.latitude.isNaN && horizon.longitude.isNaN && horizon.distance.isNaN)
    }

    @Test("Native rotation preserves public validation and state epoch")
    func boundaries() throws {
        let time = AstroTime(tt: 4, ut: 2, deltaTModel: .jplHorizons)
        for axis in [-1, 3, Int.min, Int.max] {
            #expect(throws: AstronomyError.invalidParameter) { try RotationMatrix.pivot(axis: axis, angle: 20) }
        }
        for angle in [Double.nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.invalidParameter) { try RotationMatrix.pivot(axis: 1, angle: angle) }
        }
        for observer in [
            Observer(latitude: 91, longitude: 0), Observer(latitude: 0, longitude: .nan),
            Observer(latitude: 0, longitude: 0, height: .infinity),
        ] {
            #expect(throws: AstronomyError.invalidParameter) { try observer.vector(at: time) }
            #expect(throws: AstronomyError.invalidParameter) { try observer.state(at: time) }
            #expect(throws: AstronomyError.invalidParameter) {
                try RotationMatrix.equatorialJ2000ToHorizon(at: time, from: observer)
            }
        }
        let position = Vector3D(x: 1, y: 2, z: 3, time: .init(ut: 100))
        let state = StateVector(position: position, velocity: position, time: time)
        let result = try state.rotated(by: .identity)
        #expect(result.position.time.terrestrialTime == 4)
        #expect(result.velocity.time.terrestrialTime == 4)
        #expect(result.time.deltaTModel == .jplHorizons)
        let bad = Vector3D(x: 1e200, y: 0, z: 0, time: time)
        #expect(throws: AstronomyError.badTime) { try bad.toEcliptic() }
        #expect(throws: AstronomyError.badVector) { try bad.angle(to: position) }
    }
}

//
//  NativeCoordinateValues.swift
//  AstronomyKit
//
//  Conversions between the public value types and the engine's.
//

extension Vector3D {
    func engineVector<F: Engine.Frame>(in frame: F.Type) -> Engine.Vector<F> {
        Engine.Vector(x: x, y: y, z: z, time: time.engine)
    }

    init<F>(_ vector: Engine.Vector<F>, at time: AstroTime) {
        self.init(x: vector.x, y: vector.y, z: vector.z, time: time)
    }

    /// The vector with the engine vector's own time.
    init<F>(_ vector: Engine.Vector<F>) {
        self.init(vector, at: AstroTime(vector.time))
    }
}

extension Spherical {
    var engineSpherical: Engine.Spherical {
        Engine.Spherical(latitude: latitude, longitude: longitude, distance: distance)
    }

    init(_ sphere: Engine.Spherical) {
        self.init(latitude: sphere.latitude, longitude: sphere.longitude, distance: sphere.distance)
    }
}

extension StateVector {
    init<F>(_ state: Engine.State<F>, at time: AstroTime) {
        self.init(
            position: Vector3D(x: state.x, y: state.y, z: state.z, time: time),
            velocity: Vector3D(x: state.vx, y: state.vy, z: state.vz, time: time),
            time: time
        )
    }

    func engineState(at time: Engine.Time) -> Engine.State<Engine.EQJ> {
        Engine.State(
            x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z, time: time)
    }
}

extension Horizon {
    init(_ horizontal: Engine.Horizontal) {
        self.init(
            altitude: horizontal.altitude, azimuth: horizontal.azimuth,
            rightAscension: horizontal.rightAscension, declination: horizontal.declination
        )
    }
}

extension Equatorial {
    init(_ coordinates: Engine.Equatorial, at time: AstroTime) {
        self.init(
            rightAscension: coordinates.rightAscension, declination: coordinates.declination,
            distance: coordinates.distance, time: time)
    }
}

extension Ecliptic {
    /// The coordinates, or `AstronomyError.badTime` when one is not finite.
    init(_ coordinates: Engine.Ecliptic) throws {
        self.init(latitude: coordinates.latitude, longitude: coordinates.longitude, distance: coordinates.vector.length)
        guard latitude.isFinite, longitude.isFinite, distance.isFinite else { throw AstronomyError.badTime }
    }
}

extension EclipticState {
    /// The state at `time`, the public time it was requested for.
    init(_ state: Engine.EclipticState, at time: AstroTime) {
        self.init(
            longitude: state.longitude, latitude: state.latitude, distance: state.distance,
            longitudeRate: state.longitudeRate, latitudeRate: state.latitudeRate, distanceRate: state.distanceRate,
            time: time)
    }
}

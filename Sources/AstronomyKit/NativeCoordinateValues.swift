//
//  NativeCoordinateValues.swift
//  AstronomyKit
//

extension AstroTime {
    /// The stored scales for coordinate operations, which do not derive another time.
    var coordinateTime: Engine.Time {
        Engine.Time(ut: universalTime, tt: terrestrialTime, deltaTModel: deltaTModel ?? .espenakMeeus)
    }
}

extension Vector3D {
    func engineVector<F: Engine.Frame>(in frame: F.Type) -> Engine.Vector<F> {
        Engine.Vector(x: x, y: y, z: z, time: time.coordinateTime)
    }

    init<F>(_ vector: Engine.Vector<F>, at time: AstroTime) {
        self.init(x: vector.x, y: vector.y, z: vector.z, time: time)
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
}

extension Horizon {
    init(_ horizontal: Engine.Horizontal) {
        self.init(
            altitude: horizontal.altitude, azimuth: horizontal.azimuth,
            rightAscension: horizontal.rightAscension, declination: horizontal.declination
        )
    }
}

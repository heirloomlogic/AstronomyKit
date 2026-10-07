//
//  EngineCoordinates.swift
//  AstronomyKit
//
//  Spherical, equatorial and ecliptic coordinates of engine vectors.
//

import Foundation

extension Engine {
    /// Latitude and longitude in degrees and a distance in AU.
    struct Spherical: Equatable, Sendable {
        var latitude: Double
        var longitude: Double
        var distance: Double
    }

    /// Right ascension in sidereal hours, declination in degrees and distance
    /// in AU, in the frame of the vector they came from.
    struct Equatorial: Sendable {
        var rightAscension: Double
        var declination: Double
        var distance: Double
    }

    /// A position on the true ecliptic and equinox of date, with its
    /// longitude and latitude in degrees.
    struct Ecliptic: Sendable {
        var vector: Vector<ECT>
        var latitude: Double
        var longitude: Double
    }
}

extension Engine.Spherical {
    /// The direction and length of `vector` (`Astronomy_SphereFromVector`).
    ///
    /// Longitude runs from 0 up to 360 degrees, counterclockwise from the x
    /// axis seen from +z. A vector on the z axis has longitude 0 and latitude
    /// ±90. Components that are not finite give NaN, as in the C engine.
    ///
    /// - Throws: `AstronomyError.invalidParameter` for a vector whose
    ///   squared components sum to zero.
    init<F>(_ vector: Engine.Vector<F>) throws {
        let xy = vector.x * vector.x + vector.y * vector.y
        distance = (xy + vector.z * vector.z).squareRoot()
        if xy == 0 {
            guard vector.z != 0 else { throw AstronomyError.invalidParameter }
            longitude = 0
            latitude = vector.z < 0 ? -90 : 90
        } else {
            longitude = Engine.normalized(Engine.degreesPerRadian * atan2(vector.y, vector.x), period: 360)
            latitude = Engine.degreesPerRadian * atan2(vector.z, xy.squareRoot())
        }
    }
}

extension Engine.Vector {
    /// The vector at `sphere`'s direction and distance, valid at `time`
    /// (`Astronomy_VectorFromSphere`).
    init(_ sphere: Engine.Spherical, time: Engine.Time) {
        let latitude = sphere.latitude * Engine.radiansPerDegree
        let longitude = sphere.longitude * Engine.radiansPerDegree
        let projected = sphere.distance * cos(latitude)
        self.init(
            x: projected * cos(longitude),
            y: projected * sin(longitude),
            z: sphere.distance * sin(latitude),
            time: time
        )
    }
}

extension Engine.Equatorial {
    /// The right ascension, declination and distance of `vector`
    /// (`Astronomy_EquatorFromVector`).
    ///
    /// - Throws: `AstronomyError.invalidParameter` as ``Engine/Spherical``
    ///   does.
    init<F>(_ vector: Engine.Vector<F>) throws {
        let sphere = try Engine.Spherical(vector)
        rightAscension = sphere.longitude / 15
        declination = sphere.latitude
        distance = sphere.distance
    }
}

extension Engine.Ecliptic {
    /// `vector` in the true ecliptic and equinox of its time
    /// (`Astronomy_Ecliptic`).
    ///
    /// Longitude runs from 0 up to 360 degrees; on the ecliptic pole it is 0.
    init(_ vector: Engine.Vector<Engine.EQJ>) {
        let time = vector.time
        let ecliptic = Engine.FrameRotation.eqjToEct(time).apply(to: vector)
        let projected = hypot(ecliptic.x, ecliptic.y)
        self.vector = ecliptic
        longitude =
            projected > 0 ? Engine.normalized(Engine.degreesPerRadian * atan2(ecliptic.y, ecliptic.x), period: 360) : 0
        latitude = Engine.degreesPerRadian * atan2(ecliptic.z, projected)
    }
}

extension Engine {
    /// `value`, which lies in (−period, period), moved into [0, period).
    static func normalized(_ value: Double, period: Double) -> Double {
        guard value < 0 else { return value }
        let shifted = value + period
        // A tiny negative value rounds up to the period itself.
        return shifted < period ? shifted : 0
    }
}

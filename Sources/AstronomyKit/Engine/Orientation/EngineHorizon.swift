//
//  EngineHorizon.swift
//  AstronomyKit
//
//  Horizontal coordinates and horizon vectors.
//

import Foundation

extension Engine {
    /// Where a body appears from an observer: azimuth and altitude in
    /// degrees, and the right ascension in hours and declination in degrees
    /// on the true equator of date that refraction moves it to.
    struct Horizontal: Sendable {
        var azimuth: Double
        var altitude: Double
        var rightAscension: Double
        var declination: Double
    }
}

extension Engine.Horizontal {
    /// The body at right ascension `rightAscension` hours and declination
    /// `declination` degrees on the true equator of `time`, seen from
    /// `observer` (`Astronomy_Horizon`).
    ///
    /// Azimuth runs from 0 up to 360 degrees east from north and is 0 where
    /// the direction has no horizontal component. A right ascension or
    /// declination that is not finite gives azimuth 0 and a NaN altitude, as
    /// in the C engine. With refraction, the altitude is raised by
    /// ``Engine/AtmosphericRefraction/angle(_:altitude:)``, and, unless the
    /// result is within 3e-4 degrees of the zenith or the refraction is not
    /// positive, the returned right ascension and declination move with it.
    /// Otherwise they are the inputs. The public layer validates the
    /// observer.
    init(
        time: Engine.Time,
        observer: Observer,
        rightAscension: Double,
        declination: Double,
        refraction: Refraction
    ) {
        let rotation = Engine.FrameRotation.eqdToHor(time, observer: observer)
        let ra = rightAscension * Engine.radiansPerHour
        let dec = declination * Engine.radiansPerDegree
        let p = (cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
        let direction = rotation.apply(to: Engine.Vector<Engine.EQD>(x: p.0, y: p.1, z: p.2, time: time))
        let (north, west, up) = (direction.x, direction.y, direction.z)

        let projected = hypot(north, west)
        azimuth = projected > 0 ? Engine.normalized(-atan2(west, north) * Engine.degreesPerRadian, period: 360) : 0
        var zenithDistance = atan2(projected, up) * Engine.degreesPerRadian
        self.rightAscension = rightAscension
        self.declination = declination

        let geometric = zenithDistance
        let lift = Engine.AtmosphericRefraction.angle(refraction, altitude: 90 - zenithDistance)
        zenithDistance -= lift
        if lift > 0 && zenithDistance > 3e-4 {
            // Turn the direction toward the zenith, in the plane that
            // holds both, from the geometric to the refracted distance.
            let zenith = rotation.inverse.apply(to: Engine.Vector<Engine.HOR>(x: 0, y: 0, z: 1, time: time))
            let z = (zenith.x, zenith.y, zenith.z)
            let refracted = zenithDistance * Engine.radiansPerDegree
            let unrefracted = geometric * Engine.radiansPerDegree
            let (sinNew, cosNew) = (sin(refracted), cos(refracted))
            let (sinOld, cosOld) = (sin(unrefracted), cos(unrefracted))
            let r = (
                (p.0 - cosOld * z.0) / sinOld * sinNew + z.0 * cosNew,
                (p.1 - cosOld * z.1) / sinOld * sinNew + z.1 * cosNew,
                (p.2 - cosOld * z.2) / sinOld * sinNew + z.2 * cosNew
            )
            let rProjected = hypot(r.0, r.1)
            self.rightAscension =
                rProjected > 0
                ? Engine.normalized(Engine.hoursPerRadian * atan2(r.1, r.0), period: 24) : 0
            self.declination = Engine.degreesPerRadian * atan2(r.2, rProjected)
        }
        altitude = 90 - zenithDistance
    }
}

extension Engine.Spherical {
    /// The azimuth (longitude, east from north) and altitude (latitude) of a
    /// horizon vector, with the altitude raised by `refraction`
    /// (`Astronomy_HorizonFromVector`).
    ///
    /// - Throws: `AstronomyError.invalidParameter` as
    ///   ``Engine/Spherical/init(_:)`` does.
    init(horizon vector: Engine.Vector<Engine.HOR>, refraction: Refraction) throws {
        var sphere = try Engine.Spherical(vector)
        sphere.longitude = Engine.Spherical.toggledAzimuth(sphere.longitude)
        sphere.latitude += Engine.AtmosphericRefraction.angle(refraction, altitude: sphere.latitude)
        self = sphere
    }

    /// Converts between counterclockwise longitude and clockwise azimuth, in
    /// [0, 360).
    fileprivate static func toggledAzimuth(_ degrees: Double) -> Double {
        let toggled = 360 - degrees
        if toggled >= 360 { return toggled - 360 }
        if toggled < 0 { return toggled + 360 }
        return toggled
    }
}

extension Engine.Vector where F == Engine.HOR {
    /// The horizon vector for azimuth `sphere.longitude` (east from north)
    /// and refracted altitude `sphere.latitude`, with the refraction removed
    /// (`Astronomy_VectorFromHorizon`).
    init(horizon sphere: Engine.Spherical, time: Engine.Time, refraction: Refraction) {
        var geometric = sphere
        geometric.longitude = Engine.Spherical.toggledAzimuth(sphere.longitude)
        geometric.latitude += Engine.AtmosphericRefraction.inverseAngle(refraction, altitude: sphere.latitude)
        self.init(geometric, time: time)
    }
}

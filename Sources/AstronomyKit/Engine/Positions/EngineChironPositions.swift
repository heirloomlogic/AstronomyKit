//
//  EngineChironPositions.swift
//  AstronomyKit
//
//  2060 Chiron seen from Earth's center: its light-time position and the
//  coordinates and state the public `Chiron` API reports.
//

import Foundation

extension Engine.Positions {
    /// Chiron relative to Earth's center on EQJ axes, at the time light left
    /// it for light reaching Earth at `time`, with no aberration: the public
    /// `Chiron.geocentricPosition(at:)`.
    ///
    /// Earth stays at `time`. One ``Engine/Chiron/ReusableSimulation`` serves
    /// every light-time iteration. As in the public API, the vector's time
    /// is the backdated time.
    ///
    /// The observation is checked against Chiron's supported span. The
    /// internal light-time evaluations may precede its start, including the
    /// roughly 1.56-hour backdate at the start of 1900.
    ///
    /// - Throws: `AstronomyError.badTime` for a time beyond
    ///   ``Engine/acceptedTTDays`` or outside Chiron's observation span; the
    ///   errors of ``Engine/LightTravel/correct(at:_:)`` and the simulation.
    static func chironGeocentricPosition(at time: Engine.Time) throws -> Engine.Vector<Engine.EQJ> {
        try Engine.Chiron.checkSupported(time)
        let earth = try Engine.Planet.earth.heliocentricPosition(at: time)
        let simulation = Engine.Chiron.ReusableSimulation()
        let vector = try Engine.LightTravel.correct(at: time) { backdated in
            let chiron = try simulation.heliocentricState(forLightTimeAt: backdated, observedAt: time)
            return Engine.Vector<Engine.EQJ>(
                x: chiron.x - earth.x, y: chiron.y - earth.y, z: chiron.z - earth.z, time: backdated)
        }
        return try checked(vector)
    }

    /// Chiron's position and velocity less Earth's at `time`, with no light
    /// time: the public `Chiron.geoState(at:)`.
    ///
    /// - Throws: As ``Engine/Chiron/heliocentricState(at:)`` and
    ///   ``heliocentricState(of:at:)``.
    static func chironGeocentricState(at time: Engine.Time) throws -> Engine.State<Engine.EQJ> {
        let chiron = try Engine.Chiron.heliocentricState(at: time)
        let earth = try heliocentricState(of: .earth, at: time)
        return try checked(
            Engine.State(
                position: chiron.positionVector - earth.positionVector,
                velocity: chiron.velocityVector - earth.velocityVector, time: time))
    }

    /// The right ascension, declination and distance of
    /// ``chironGeocentricPosition(at:)`` on the J2000 equator: the public
    /// `Chiron.equatorial(at:)`.
    ///
    /// - Throws: As ``chironGeocentricPosition(at:)``.
    static func chironEquatorial(at time: Engine.Time) throws -> Engine.Equatorial {
        try Engine.Equatorial(try chironGeocentricPosition(at: time))
    }

    /// ``chironGeocentricPosition(at:)`` on the true ecliptic and equinox of
    /// its backdated time, as the public `Chiron.ecliptic(at:)` converts it.
    ///
    /// - Throws: As ``chironGeocentricPosition(at:)``.
    static func chironEcliptic(at time: Engine.Time) throws -> Engine.Ecliptic {
        Engine.Ecliptic(try chironGeocentricPosition(at: time))
    }

    /// Where Chiron appears in `observer`'s sky: the geocentric
    /// ``chironGeocentricPosition(at:)``, with no parallax or aberration as
    /// in the public `Chiron.horizon(at:from:refraction:)`, on the true
    /// equator of `time`, through ``Engine/Horizontal``.
    ///
    /// - Throws: As ``chironGeocentricPosition(at:)``.
    static func chironHorizontal(
        at time: Engine.Time, from observer: Observer, refraction: Refraction
    ) throws -> Engine.Horizontal {
        var vector = try chironGeocentricPosition(at: time)
        vector.time = time
        let equatorial = try coordinates(Engine.FrameRotation.eqjToEqd(time).apply(to: vector))
        return Engine.Horizontal(
            time: time, observer: observer, rightAscension: equatorial.rightAscension,
            declination: equatorial.declination, refraction: refraction)
    }
}

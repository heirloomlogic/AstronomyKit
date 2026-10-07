//
//  EngineRefraction.swift
//  AstronomyKit
//
//  Atmospheric refraction near the horizon and its inverse.
//

import Foundation

extension Engine {
    /// Atmospheric refraction near the horizon. The public `Refraction`
    /// option selects the model.
    enum AtmosphericRefraction {}
}

extension Engine.AtmosphericRefraction {
    /// The refraction in degrees that raises a body at geometric `altitude`
    /// degrees (`Astronomy_Refraction`).
    ///
    /// Both `.normal` and `.jplHorizons` use Sæmundsson's formula as Meeus
    /// gives it (Astronomical Algorithms, 2nd ed., eq. 16.4):
    /// R = 1.02′ / tan(h + 10.3°/(h + 5.11)), with h held at −1° below that
    /// altitude, as JPL Horizons does. `.normal` then scales the refraction
    /// below −1° down linearly to zero at −90°. `.none`, and an altitude
    /// outside −90 to 90, give 0; a NaN altitude gives NaN.
    static func angle(_ refraction: Refraction, altitude: Double) -> Double {
        guard refraction != .none, !(altitude < -90 || altitude > 90) else { return 0 }
        let h = altitude < -1 ? -1 : altitude
        let arcminutes = 1.02 / tan((h + 10.3 / (h + 5.11)) * Engine.radiansPerDegree)
        let degrees = arcminutes / 60
        if refraction == .normal && altitude < -1 {
            return degrees * (altitude + 90) / 89
        }
        return degrees
    }

    /// The correction in degrees that takes an apparent, refracted
    /// `altitude` back to the geometric one (`Astronomy_InverseRefraction`):
    /// adding it to `altitude` gives an altitude whose refraction leads back
    /// to `altitude` within 1e-14 degrees.
    ///
    /// Returns 0 for an altitude that is not finite or is outside −90 to 90,
    /// for `.none`, and where the iteration finds no such altitude within
    /// 1,000 steps. Below −1° with `.normal`, where refracted altitudes skip
    /// some doubles, an iteration that alternates between the two neighbors
    /// of `altitude` returns the lower one.
    static func inverseAngle(_ refraction: Refraction, altitude bent: Double) -> Double {
        guard (-90...90).contains(bent) else { return 0 }
        var altitude = bent - angle(refraction, altitude: bent)
        var previous = Double.nan
        for _ in 0..<1000 {
            let difference = altitude + angle(refraction, altitude: altitude) - bent
            guard difference.isFinite else { return 0 }
            if abs(difference) < 1e-14 { return altitude - bent }
            let next = altitude - difference
            if next == previous {
                // A two-cycle between adjacent doubles brackets `bent`; a
                // wider cycle spans the jump at the edge of the model's range.
                let lower = min(previous, altitude)
                return lower.nextUp == max(previous, altitude) ? lower - bent : 0
            }
            guard next.isFinite, next != altitude else { return 0 }
            previous = altitude
            altitude = next
        }
        return 0
    }
}

//
//  EngineRefractionTests.swift
//  AstronomyKit
//
//  Refraction and its inverse against Sæmundsson's formula.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.AtmosphericRefraction")
struct EngineRefractionTests {
    typealias Model = Engine.AtmosphericRefraction

    /// Sæmundsson's formula, Meeus, Astronomical Algorithms (2nd ed.),
    /// eq. 16.4: R = 1.02 / tan(h + 10.3 / (h + 5.11)) arcminutes, h in
    /// degrees, transcribed here in degrees.
    static func saemundsson(_ h: Double) -> Double {
        1.02 / tan((h + 10.3 / (h + 5.11)) * .pi / 180) / 60
    }

    @Test("Above -1 degree both models are Sæmundsson's formula", arguments: [-1.0, -0.5, 0, 0.5, 5, 30, 60, 89.9])
    func formula(altitude: Double) {
        let expected = Self.saemundsson(altitude)
        #expect(abs(Model.angle(.normal, altitude: altitude) - expected) <= 1e-15)
        #expect(abs(Model.angle(.jplHorizons, altitude: altitude) - expected) <= 1e-15)
    }

    @Test("At the horizon the refraction is about 29 arcminutes")
    func horizon() {
        #expect(abs(Model.angle(.normal, altitude: 0) * 60 - 28.98) <= 0.01)
    }

    @Test("Below -1 degree JPL Horizons holds the -1 degree value and normal tapers to zero at the nadir")
    func belowHorizon() {
        let atMinusOne = Self.saemundsson(-1)
        for altitude in [-1.5, -10, -45, -89] {
            #expect(Model.angle(.jplHorizons, altitude: altitude) == Model.angle(.jplHorizons, altitude: -1))
            let tapered = atMinusOne * (altitude + 90) / 89
            #expect(abs(Model.angle(.normal, altitude: altitude) - tapered) <= 1e-15)
        }
        #expect(Model.angle(.normal, altitude: -90) == 0)
        #expect(abs(Model.angle(.jplHorizons, altitude: -90) - atMinusOne) <= 1e-15)
    }

    @Test(
        "No refraction, and altitudes outside -90 to 90, give 0",
        arguments: [(Refraction.none, 10.0), (.normal, 90.000_1), (.normal, -90.000_1), (.jplHorizons, 1e300)]
    )
    func zero(refraction: Refraction, altitude: Double) {
        #expect(Model.angle(refraction, altitude: altitude) == 0)
    }

    @Test("A NaN altitude gives NaN")
    func nanAltitude() {
        #expect(Model.angle(.normal, altitude: .nan).isNaN)
        #expect(Model.angle(.none, altitude: .nan) == 0)
    }

    @Test(
        "The inverse undoes the refraction",
        arguments: [-89.5, -45, -5, -1, -0.25, 0, 0.5, 10, 45, 89.99]
    )
    func inverse(bent: Double) {
        // JPL Horizons mode lifts everything below -1° by 0.6466°, so no
        // altitude in range refracts to below -89.35°.
        let models: [Refraction] = bent < -89 ? [.normal] : [.normal, .jplHorizons]
        for refraction in models {
            let correction = Model.inverseAngle(refraction, altitude: bent)
            let geometric = bent + correction
            let refracted = geometric + Model.angle(refraction, altitude: geometric)
            #expect(abs(refracted - bent) <= 1e-13, "\(refraction) at \(bent)")
        }
    }

    @Test(
        "The inverse gives 0 outside -90 to 90",
        arguments: [Double.nan, .infinity, 90.5, -91]
    )
    func inverseZero(bent: Double) {
        #expect(Model.inverseAngle(.normal, altitude: bent) == 0)
    }

    @Test("Without refraction the inverse is 0")
    func inverseNone() {
        #expect(Model.inverseAngle(.none, altitude: 10) == 0)
    }

    @Test("Where no altitude in range refracts to the given one, the inverse gives 0")
    func inverseUnreachable() {
        #expect(Model.inverseAngle(.jplHorizons, altitude: -89.5) == 0)
    }

    /// Below -1° the normal model rises faster than the altitude, so for
    /// some refracted altitudes no double refracts to them exactly; the
    /// iteration then alternates between the two neighbours and returns the
    /// lower one, which refracts to within one ulp.
    @Test("Every refracted altitude below -64 degrees inverts to within one ulp")
    func skippedDoubles() {
        var bent = -80.0
        for _ in 0..<2_000 {
            let geometric = bent + Model.inverseAngle(.normal, altitude: bent)
            let refracted = geometric + Model.angle(.normal, altitude: geometric)
            #expect(abs(refracted - bent) <= bent.ulp, "\(bent)")
            bent = bent.nextUp
        }
    }
}

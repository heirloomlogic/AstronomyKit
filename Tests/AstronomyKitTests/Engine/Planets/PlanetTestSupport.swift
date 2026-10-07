//
//  PlanetTestSupport.swift
//  AstronomyKit
//
//  Times, caches and Horizons records shared by the planet suites.
//

@testable import AstronomyKit

enum PlanetTestSupport {
    /// A time at `tt` whose UT the planet functions do not read.
    static func time(tt: Double) -> Engine.Time {
        Engine.Time(ut: tt, tt: tt, deltaTModel: .espenakMeeus)
    }

    /// A cache with its own registry, so its counts and entries do not
    /// depend on other suites.
    static func makeCache(capacity: Int = 32) -> (Engine.VSOP87B.Cache, Engine.CacheRegistry) {
        let registry = Engine.CacheRegistry()
        return (Engine.VSOP87B.Cache(capacity: capacity, registry: registry), registry)
    }

    /// The heliocentric planet records in `distance-fixtures.json`, from the
    /// JPL Horizons vectors in `Scripts/reference-data/sources/distance/heldout`.
    static let heliocentric: [(planet: Engine.Planet, reference: DistanceReferenceArchive.Reference)] =
        DistanceReferenceArchive.shared.references.compactMap { reference in
            guard reference.mode == "heliocentric",
                let body = CelestialBody.allCases.first(where: { $0.name == reference.body }),
                let planet = Engine.Planet(body)
            else { return nil }
            return (planet, reference)
        }
}

//
//  EnginePositionsHorizonsTests.swift
//  AstronomyKit
//
//  The composed positions against JPL Horizons: barycentric states within
//  Astronomy Engine's limits, every DistanceAccuracyTests record, and the
//  Moon's JPLValidationTests suites through the geocentric function.
//

import Foundation
import Testing

@testable import AstronomyKit

extension PlutoSegmentSuites {
    /// In `PlutoSegmentSuites` because Pluto's 1900-01-01 state is in the
    /// DE440 blend, which reads a segment of the integrated model.
    @Suite("Engine barycentric states against JPL Horizons")
    struct EnginePositionsHorizonsTests {
        typealias Positions = Engine.Positions

        // MARK: - Barycentric states

        /// The limits of Astronomy Engine's `BaryStateTest` (`ctest.c` at the
        /// pinned revision) on position and velocity: relative to the
        /// published vector's length, or for the Sun, whose barycentric
        /// distance can approach zero, absolute in AU and AU per day.
        static let limits: [String: (position: Double, velocity: Double, relative: Bool)] = [
            "sun": (1.224e-5, 1.134e-7, false),
            "mercury": (1.672e-4, 2.698e-4, true),
            "venus": (4.123e-5, 4.308e-5, true),
            "earth": (2.296e-5, 6.359e-5, true),
            "mars": (3.107e-5, 5.550e-5, true),
            "jupiter": (7.389e-5, 2.471e-4, true),
            "saturn": (1.067e-4, 3.220e-4, true),
            "uranus": (9.035e-5, 2.519e-4, true),
            "neptune": (9.838e-5, 4.446e-4, true),
            "pluto": (4.259e-5, 7.827e-5, true),
            "moon": (2.354e-5, 6.604e-5, true),
            "emb": (2.353e-5, 6.511e-5, true),
        ]

        /// Horizons' states relative to the solar system barycenter, from
        /// `sources/horizons/*-barycentric-vector.json`.
        static let states = IndependentReferenceArchive.shared.vectors.filter {
            $0.origin == "barycenter"
        }

        /// The body of a record named `<body>-barycentric`.
        static func body(named name: String) throws -> CelestialBody {
            let body = name.replacing("-barycentric", with: "")
            if body == "emb" { return .earthMoonBarycenter }
            return try #require(CelestialBody.allCases.first { $0.name.lowercased() == body })
        }

        /// The difference `StateVectorDiff` measures: the length of
        /// `actual − expected`, over the length of `expected` when relative.
        static func difference(_ actual: SIMD3<Double>, _ expected: SIMD3<Double>, relative: Bool) -> Double {
            relative
                ? EngineMoonStatesTests.relativeError(actual, expected) : EngineGravityTests.length(actual - expected)
        }

        /// The position and velocity differences of the engine's state for
        /// `body` at a Horizons epoch.
        static func errors(
            _ body: CelestialBody, _ reference: IndependentReferenceArchive.Vector, relative: Bool
        ) throws -> (position: Double, velocity: Double) {
            let time = PlanetTestSupport.time(tt: EnginePlutoHorizonsTests.tt(reference))
            let state = try Positions.barycentricState(of: body, at: time)
            let expected = EngineMoonStatesTests.eqj(reference.velocityAUPerDay)
            return (
                difference(
                    state.positionVector, EnginePlutoHorizonsTests.expected(reference), relative: relative),
                difference(state.velocityVector, expected, relative: relative)
            )
        }

        @Test("Barycentric states within Astronomy Engine's BaryStateTest limits")
        func barycentricStates() throws {
            // The Sun, Jupiter to Neptune and Pluto at 9 dates; Mercury to
            // Mars, the Moon and the Earth-Moon barycenter at 5.
            #expect(Self.states.count == 6 * 9 + 6 * 5)
            #expect(Set(Self.states.map(\.body)) == Set(Self.limits.keys.map { "\($0)-barycentric" }))
            for reference in Self.states {
                let body = try Self.body(named: reference.body)
                let limit = try #require(Self.limits[reference.body.replacing("-barycentric", with: "")])
                let (position, velocity) = try Self.errors(body, reference, relative: limit.relative)
                #expect(position <= limit.position, "\(reference.body) \(reference.tdb): \(position)")
                #expect(velocity <= limit.velocity, "\(reference.body) \(reference.tdb): \(velocity)")
            }
        }

        @Test(
            "The barycentric checks fail for the heliocentric Sun, the barycenter as the Moon, or a day off"
        )
        func barycentricNegativeControls() throws {
            let sunReference = try #require(Self.states.first { $0.body == "sun-barycentric" })
            let time = PlanetTestSupport.time(tt: EnginePlutoHorizonsTests.tt(sunReference))
            let heliocentric = try Positions.heliocentricState(of: .sun, at: time).positionVector
            let expected = EnginePlutoHorizonsTests.expected(sunReference)
            #expect(Self.difference(heliocentric, expected, relative: false) > 1.224e-5)

            let moonReference = try #require(Self.states.first { $0.body == "moon-barycentric" })
            #expect(
                try Self.errors(.earthMoonBarycenter, moonReference, relative: true).position > 2.354e-5)

            let marsReference = try #require(Self.states.first { $0.body == "mars-barycentric" })
            let late = PlanetTestSupport.time(tt: EnginePlutoHorizonsTests.tt(marsReference) + 1)
            let mars = try Positions.barycentricState(of: .mars, at: late).positionVector
            let marsExpected = EnginePlutoHorizonsTests.expected(marsReference)
            #expect(Self.difference(mars, marsExpected, relative: true) > 3.107e-5)
        }
    }
}

/// The composed positions against the DistanceAccuracyTests and
/// JPLValidationTests references. Pluto's records here are inside the DE440
/// span, so they read no segment of its integrated model.
@Suite("Engine positions against the distance and Moon references")
struct EnginePositionsReferenceTests {
    typealias Positions = Engine.Positions

    // MARK: - Distances

    /// Every record of `distance-fixtures.json` with its body and its
    /// time on the fixture's TT.
    static let distanceRecords: [(body: CelestialBody, time: Engine.Time, DistanceReferenceArchive.Reference)] =
        DistanceReferenceArchive.shared.references.compactMap { reference in
            guard let body = CelestialBody.allCases.first(where: { $0.name == reference.body }) else {
                return nil
            }
            let time = Engine.Time(tt: reference.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
            return (body, time, reference)
        }

    /// `DistanceAccuracyTests` on the composed functions: the heliocentric
    /// distance, and the length of the geocentric position with no
    /// aberration, which Horizons' light-time ranges match.
    @Test("Every DistanceAccuracyTests record within its allowance")
    func distances() throws {
        #expect(Self.distanceRecords.count == 2_546)
        for (body, time, reference) in Self.distanceRecords {
            let range =
                reference.mode == "heliocentric"
                ? try Positions.heliocentricDistance(of: body, at: time)
                : try Positions.geocentricPosition(of: body, at: time, aberration: .none).length
            let errorKm = abs(range - reference.referenceRangeAU) * Engine.kilometersPerAU
            #expect(
                errorKm <= reference.allowedErrorKm,
                "\(reference.body) \(reference.mode) JD TT \(reference.julianDateTT): \(errorKm) km")
        }
    }

    @Test("The distance checks fail for the wrong mode, aberration or day")
    func distanceNegativeControls() throws {
        let (_, time, geocentric) = try #require(
            Self.distanceRecords.first { $0.body == .mars && $0.2.mode == "geocentric" })
        func misses(_ range: Double) -> Bool {
            abs(range - geocentric.referenceRangeAU) * Engine.kilometersPerAU
                > geocentric.allowedErrorKm
        }
        #expect(misses(try Positions.heliocentricDistance(of: .mars, at: time)))
        #expect(
            misses(try Positions.geocentricPosition(of: .mars, at: time, aberration: .corrected).length)
        )
        #expect(
            misses(
                try Positions.geocentricPosition(of: .mars, at: time.adding(days: 1), aberration: .none)
                    .length))
    }

    // MARK: - The Moon's JPLValidationTests suites

    /// The geocentric position the public API reads, with no light time,
    /// against the astrometric rows of the Moon's suites. The light time
    /// moves the Moon by about 0.7″, far inside the 1′ allowance.
    @Test("The JPLValidationTests geocentric and Asheville Moon suites within their 1′")
    func moon() throws {
        let suites: [(Observer?, [JPLReferencePoint])] = [
            (nil, MoonValidationTests.referenceData),
            (ashevilleObserver, AshevilleValidationTests.moonData),
        ]
        for (observer, references) in suites {
            #expect(references.count == 4)
            for reference in references {
                let time = EnginePlanetHorizonsTests.time(reference)
                var vector = try Positions.geocentricPosition(of: .moon, at: time, aberration: .none)
                if let observer {
                    let site = Engine.Observers.vector(observer, at: time)
                    vector = Engine.Vector(
                        x: vector.x - site.x, y: vector.y - site.y, z: vector.z - site.z, time: time)
                }
                let arcminutes = try EnginePlanetHorizonsTests.separation(vector, reference)
                #expect(
                    arcminutes <= toleranceArcminutes, "\(reference.month)-\(reference.day): \(arcminutes)′"
                )
            }
        }
    }
}

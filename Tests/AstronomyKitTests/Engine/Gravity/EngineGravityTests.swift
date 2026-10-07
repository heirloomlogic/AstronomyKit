//
//  EngineGravityTests.swift
//  AstronomyKit
//
//  The masses, the major bodies' barycentric states, the pull on a small
//  body and one integrator step.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Gravity")
struct EngineGravityTests {
    typealias Gravity = Engine.Gravity

    static func length(_ v: SIMD3<Double>) -> Double { (v * v).sum().squareRoot() }

    /// DE405's constants (Standish 1998, JPL IOM 312.F-98-048): the Sun's GM
    /// is k², and the planets' are the Sun's divided by the published mass
    /// ratios, GM☉/GM.
    @Test("GM values against DE405's Gaussian constant and mass ratios")
    func masses() {
        let k = 0.01720209895
        #expect(abs(Gravity.sunGM - k * k) <= Gravity.sunGM.ulp)
        for (gm, ratio) in [
            (Gravity.jupiterGM, 1_047.3486), (Gravity.saturnGM, 3_497.898), (Gravity.uranusGM, 22_902.98),
            (Gravity.neptuneGM, 19_412.24),
        ] {
            // DE405 derives each GM from the ratio, so they agree to 1.4e-11.
            #expect(abs(Gravity.sunGM / gm / ratio - 1) <= 1e-10, "ratio \(ratio)")
        }
    }

    /// DE405 gives Earth and the Earth-Moon system separately; the
    /// simulation pulls with the system, Earth's GM times 1 + 1/81.30056.
    @Test("The inner planets' GM against DE405's mass ratios, Earth's with the Moon's")
    func innerMasses() {
        for (gm, ratio) in [
            (Gravity.mercuryGM, 6_023_600.0), (Gravity.venusGM, 408_523.71),
            (Gravity.SolarSystem.planetGM[2], 328_900.5614), (Gravity.marsGM, 3_098_708),
        ] {
            #expect(abs(Gravity.sunGM / gm / ratio - 1) <= 1e-10, "ratio \(ratio)")
        }
        for (planet, gm) in [
            (Engine.Planet.mercury, Gravity.mercuryGM), (.venus, Gravity.venusGM), (.mars, Gravity.marsGM),
            (.jupiter, Gravity.jupiterGM), (.saturn, Gravity.saturnGM), (.uranus, Gravity.uranusGM),
            (.neptune, Gravity.neptuneGM),
        ] {
            #expect(Gravity.SolarSystem.planetGM[planet.rawValue] == gm, "\(planet)")
        }
    }

    @Test("The solar system: the Sun opposes all eight planets' offset, and each planet keeps its heliocentric state")
    func solarSystem() throws {
        for tt in [0.0, -400_000.25] {
            let system = try Gravity.SolarSystem(tt: tt)
            let time = PlanetTestSupport.time(tt: tt)
            var offset = SIMD3<Double>.zero
            for planet in Engine.Planet.allCases {
                let state = try planet.heliocentricState(at: time)
                let position = SIMD3(state.x, state.y, state.z)
                let celestial = try #require(CelestialBody(rawValue: Int32(planet.rawValue)))
                let body = try #require(system.state(of: celestial))
                #expect(Self.length(body.position - system.sun.position - position) <= 1e-14, "\(planet) at \(tt)")
                let gm = Gravity.SolarSystem.planetGM[planet.rawValue]
                offset += gm / (gm + Gravity.sunGM) * position
            }
            #expect(Self.length(system.sun.position + offset) <= 1e-17)
            let barycenter = try #require(system.state(of: .solarSystemBarycenter))
            #expect(barycenter.position == .zero && barycenter.velocity == .zero)
            #expect(system.state(of: .sun)?.position == system.sun.position)
            for body in [CelestialBody.pluto, .moon, .earthMoonBarycenter, .io] {
                #expect(system.state(of: body) == nil)
            }
            // The pull of all nine bodies, from the Sun outward.
            let at = SIMD3(3.0, -4, 1)
            var expected = SIMD3<Double>.zero
            for (gm, body) in zip([Gravity.sunGM] + Gravity.SolarSystem.planetGM, [system.sun] + system.planets) {
                let d = body.position - at
                expected += gm * d / pow(Self.length(d), 3)
            }
            #expect(Self.length(system.acceleration(at: at) - expected) <= 1e-15 * Self.length(expected))
        }
    }

    @Test("The integrator reads the planets without storing them")
    func seriesCache() throws {
        let stores = Gravity.seriesCache.coordinates + Gravity.seriesCache.derivatives
        #expect(stores.allSatisfy { $0.capacity == 0 })
        let jupiter = Gravity.seriesCache.coordinates[Engine.Planet.jupiter.rawValue]
        let before = jupiter.statistics.misses
        _ = try Gravity.MajorBodies(tt: -400_000.25)
        #expect(jupiter.statistics.misses > before)
        #expect(stores.allSatisfy { $0.count == 0 })
    }

    @Test(
        "The major bodies: the Sun opposes the planets' mass-weighted offset, and each planet keeps its heliocentric state"
    )
    func majorBodies() throws {
        // Inside the polynomial span and outside it, in the series.
        for tt in [0.0, 12_345.5, -400_000.25, 700_000.75] {
            let bodies = try Gravity.MajorBodies(tt: tt)
            let time = PlanetTestSupport.time(tt: tt)
            var offset = SIMD3<Double>.zero
            var offsetVelocity = SIMD3<Double>.zero
            for (planet, gm, body) in [
                (Engine.Planet.jupiter, Gravity.jupiterGM, bodies.jupiter), (.saturn, Gravity.saturnGM, bodies.saturn),
                (.uranus, Gravity.uranusGM, bodies.uranus), (.neptune, Gravity.neptuneGM, bodies.neptune),
            ] {
                let state = try planet.heliocentricState(at: time)
                let position = SIMD3(state.x, state.y, state.z)
                let velocity = SIMD3(state.vx, state.vy, state.vz)
                #expect(Self.length(body.position - bodies.sun.position - position) <= 1e-14, "\(planet) at \(tt)")
                #expect(Self.length(body.velocity - bodies.sun.velocity - velocity) <= 1e-18, "\(planet) at \(tt)")
                offset += gm / (gm + Gravity.sunGM) * position
                offsetVelocity += gm / (gm + Gravity.sunGM) * velocity
            }
            #expect(Self.length(bodies.sun.position + offset) <= 1e-17, "tt \(tt)")
            #expect(Self.length(bodies.sun.velocity + offsetVelocity) <= 1e-20, "tt \(tt)")
            // The Sun stays within about 0.01 AU of the barycenter.
            #expect(Self.length(bodies.sun.position) < 0.011)
        }
    }

    @Test("The acceleration is Newton's inverse-square pull of the five bodies")
    func acceleration() throws {
        let bodies = try Gravity.MajorBodies(tt: 3_652.5)
        for position in [SIMD3(30.0, -5, 2), SIMD3(-1.5, 0.25, 0.75), SIMD3(5.2, 0, 0)] {
            var expected = SIMD3<Double>.zero
            for (gm, body) in [
                (Gravity.sunGM, bodies.sun), (Gravity.jupiterGM, bodies.jupiter), (Gravity.saturnGM, bodies.saturn),
                (Gravity.uranusGM, bodies.uranus), (Gravity.neptuneGM, bodies.neptune),
            ] {
                let d = body.position - position
                expected += gm * d / pow(Self.length(d), 3)
            }
            let acceleration = bodies.acceleration(at: position)
            #expect(Self.length(acceleration - expected) <= 1e-15 * Self.length(expected), "\(position)")
        }
        // Far out it tends to the pull of the whole mass at the barycenter.
        let far = SIMD3(1e4, 0, 0)
        let total = Gravity.sunGM + Gravity.jupiterGM + Gravity.saturnGM + Gravity.uranusGM + Gravity.neptuneGM
        let pull = bodies.acceleration(at: far)
        #expect(abs(pull.x + total / 1e8) <= 1e-6 * total / 1e8)
    }

    @Test("The position and velocity updates are the constant-acceleration formulas")
    func updates() {
        let r = SIMD3(1.0, -2, 3)
        let v = SIMD3(0.5, 0.25, -0.125)
        let a = SIMD3(-0.0625, 0.03125, 0.5)
        for dt in [0.0, 146, -146, 2.5] {
            #expect(Gravity.position(after: dt, from: r, velocity: v, acceleration: a) == r + v * dt + a * dt * dt / 2)
            #expect(Gravity.velocity(after: dt, from: v, acceleration: a) == v + a * dt)
        }
    }

    /// One step's error is third order in its length: a step of half the
    /// length lands about eight times closer to a finely integrated
    /// reference.
    @Test("A step's error is third order in its length, forward and backward")
    func stepOrder() throws {
        let state = Engine.Pluto.stateTable[25]
        let start = try Gravity.start(state).step
        func integrate(_ span: Double, steps: Int) throws -> SIMD3<Double> {
            var step = start
            for k in 1...steps {
                step = try Gravity.advance(step, to: start.tt + span * Double(k) / Double(steps)).step
            }
            return step.position
        }
        func error(_ span: Double) throws -> Double {
            Self.length(try integrate(span, steps: 1) - integrate(span, steps: 64))
        }
        for span in [292.0, -292] {
            let ratio = try error(span) / error(span / 2)
            #expect(ratio > 7 && ratio < 9, "span \(span): \(ratio)")
        }
    }

    @Test("A step starts from the heliocentric state moved to the barycenter, and lands on its time")
    func start() throws {
        let state = Engine.Pluto.stateTable[24]
        let (step, bodies) = try Gravity.start(state)
        #expect(step.tt == state.tt)
        #expect(step.position == state.position + bodies.sun.position)
        #expect(step.velocity == state.velocity + bodies.sun.velocity)
        #expect(step.acceleration == bodies.acceleration(at: step.position))
        let next = try Gravity.advance(step, to: state.tt - 73)
        #expect(next.step.tt == state.tt - 73)
        #expect(next.step.acceleration == next.bodies.acceleration(at: next.step.position))
    }

    @Test("A time outside the accepted range throws badTime")
    func badTime() {
        for tt in [Double.nan, .infinity, Engine.acceptedTTDays.nextUp] {
            #expect(throws: AstronomyError.badTime) { _ = try Gravity.MajorBodies(tt: tt) }
        }
    }
}

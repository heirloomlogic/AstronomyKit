//
//  EngineGravitySimulationTests.swift
//  AstronomyKit
//
//  The gravity simulation: Horizons states reached forward and backward,
//  origins, body counts, swaps, repeated times and failed updates.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.GravitySimulation")
struct EngineGravitySimulationTests {
    typealias Simulation = Engine.GravitySimulation

    static func time(tt: Double) -> Engine.Time { PlanetTestSupport.time(tt: tt) }

    static func state(_ position: SIMD3<Double>, _ velocity: SIMD3<Double>, tt: Double) -> Engine.State<Engine.EQJ> {
        Engine.State(
            x: position.x, y: position.y, z: position.z, vx: velocity.x, vy: velocity.y, vz: velocity.z,
            time: time(tt: tt))
    }

    static func bits(_ states: [Engine.State<Engine.EQJ>]) -> [UInt64] {
        states.flatMap { [$0.x, $0.y, $0.z, $0.vx, $0.vy, $0.vz].map(\.bitPattern) }
    }

    static func bits(_ moment: Simulation.Moment) -> [UInt64] {
        [moment.time.ut, moment.time.tt].map(\.bitPattern)
            + moment.bodies.flatMap { step in
                [step.tt] + [step.position, step.velocity, step.acceleration].flatMap { [$0.x, $0.y, $0.z] }
            }.map(\.bitPattern)
            + ([moment.solarSystem.sun] + moment.solarSystem.planets).flatMap {
                [$0.position.x, $0.position.y, $0.position.z, $0.velocity.x, $0.velocity.y, $0.velocity.z]
            }.map(\.bitPattern)
    }

    static func length(_ v: SIMD3<Double>) -> Double { EngineGravityTests.length(v) }

    /// Two heliocentric bodies at TT 0.25: one near Pluto, one inside
    /// Jupiter's orbit.
    static let t0 = 0.25
    static let bodies = [
        state(SIMD3(-9.8, -27.9, -5.7), SIMD3(3.0e-3, -1.1e-3, -1.2e-3), tt: t0),
        state(SIMD3(2.5, 1.0, -0.3), SIMD3(-2.0e-3, 9e-3, 1e-4), tt: t0),
    ]

    /// Steps `simulation` from its time to `tt` in `count` equal steps.
    @discardableResult
    static func step(_ simulation: Simulation, to tt: Double, count: Int) throws -> [Engine.State<Engine.EQJ>] {
        let start = simulation.time.tt
        var states: [Engine.State<Engine.EQJ>] = []
        for k in 1...count {
            states = try simulation.update(to: time(tt: start + (tt - start) * Double(k) / Double(count)))
        }
        return states
    }

    // MARK: - Against JPL Horizons

    /// Horizons' Pluto system barycenter on 1990, 2000, 2001 and 2010-01-01
    /// (`sources/horizons/pluto-barycenter-decade.json`). The simulation
    /// starts from the 2000 state and steps a day at a time. It lands within
    /// 2,700 km and 0.12″ of Horizons after ten years either way, and within
    /// 1.5e-6 of the speed; the bounds are 10,000 km, 0.5″ and 5e-6. The
    /// difference is the force model's, VSOP87B planets with DE405 masses
    /// against DE441: steps of 4 and 16 days land as close.
    @Test("Forward and backward from a Horizons state to Horizons states a year and a decade away")
    func horizons() throws {
        let references = IndependentReferenceArchive.shared.vectors.filter { $0.body == "pluto-barycenter-decade" }
        #expect(references.count == 4)
        let start = try #require(references.first { $0.julianDateTDB == 2_451_544.5 })
        typealias Horizons = PlutoSegmentSuites.EnginePlutoHorizonsTests
        let position = EngineMoonStatesTests.eqj(start.positionAU)
        let velocity = EngineMoonStatesTests.eqj(start.velocityAUPerDay)
        let t0 = Horizons.tt(start)
        for reference in references where reference.julianDateTDB != start.julianDateTDB {
            let simulation = try Simulation(
                origin: .sun, time: Self.time(tt: t0), states: [Self.state(position, velocity, tt: t0)])
            let target = Horizons.tt(reference)
            let state = try #require(
                try Self.step(simulation, to: target, count: Int(abs(target - t0).rounded(.up))).first)
            let expectedVelocity = EngineMoonStatesTests.eqj(reference.velocityAUPerDay)
            let km = Self.length(state.positionVector - Horizons.expected(reference)) * Engine.kilometersPerAU
            let arcseconds = try Horizons.arcminutes(state.positionVector, reference) * 60
            let relative = Self.length(state.velocityVector - expectedVelocity) / Self.length(expectedVelocity)
            #expect(km <= 10_000, "\(reference.tdb): \(km) km")
            #expect(arcseconds <= 0.5, "\(reference.tdb): \(arcseconds)″")
            #expect(relative <= 5e-6, "\(reference.tdb): \(relative)")
        }
    }

    // MARK: - Construction

    @Test("A new simulation holds the states at its time in both moments")
    func initial() throws {
        let simulation = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        #expect(simulation.origin == .sun && simulation.bodyCount == 2)
        #expect(simulation.time.tt == Self.t0)
        let (current, previous) = simulation.moments
        #expect(Self.bits(current) == Self.bits(previous))
        // The states come back at the same TT, barycentric and back.
        let states = try simulation.update(to: Self.time(tt: Self.t0))
        for (state, body) in zip(states, Self.bodies) {
            #expect(Self.length(state.positionVector - body.positionVector) <= 1e-14)
            #expect(Self.length(state.velocityVector - body.velocityVector) <= 1e-18)
        }
    }

    @Test("A simulation with no bodies steps the Sun and planets and returns no states")
    func noBodies() throws {
        let simulation = try Simulation(origin: .earth, time: Self.time(tt: Self.t0), states: [])
        #expect(simulation.bodyCount == 0)
        #expect(try simulation.update(to: Self.time(tt: 100)).isEmpty)
        let earth = try simulation.state(of: .earth)
        #expect([earth.x, earth.y, earth.z, earth.vx, earth.vy, earth.vz] == [0, 0, 0, 0, 0, 0])
        #expect(earth.time.tt == 100)
    }

    @Test(
        "The origin must be the Sun, a planet or the barycenter",
        arguments: [CelestialBody.pluto, .moon, .earthMoonBarycenter, .io])
    func unsupportedOrigin(origin: CelestialBody) {
        #expect(throws: AstronomyError.invalidBody) {
            _ = try Simulation(origin: origin, time: Self.time(tt: Self.t0), states: Self.bodies)
        }
    }

    /// The C engine checks the origin's range, then the time, then the
    /// states' times, and only then whether it models the origin.
    @Test("Errors come in the C engine's order")
    func errorOrder() {
        let badTime = Self.time(tt: Engine.acceptedTTDays.nextUp)
        #expect(throws: AstronomyError.invalidBody) { _ = try Simulation(origin: .io, time: badTime, states: []) }
        #expect(throws: AstronomyError.badTime) { _ = try Simulation(origin: .moon, time: badTime, states: []) }
        for tt in [Double.nan, .infinity, -Engine.acceptedTTDays.nextUp] {
            #expect(throws: AstronomyError.badTime) {
                _ = try Simulation(origin: .sun, time: Self.time(tt: tt), states: [])
            }
        }
        let late = [Self.bodies[0], Self.state(SIMD3(1, 0, 0), SIMD3(0, 0.017, 0), tt: Self.t0 + 1e-9)]
        #expect(throws: AstronomyError.inconsistentTimes) {
            _ = try Simulation(origin: .moon, time: Self.time(tt: Self.t0), states: late)
        }
        #expect(throws: AstronomyError.invalidBody) {
            _ = try Simulation(origin: .moon, time: Self.time(tt: Self.t0), states: Self.bodies)
        }
    }

    // MARK: - Updates

    @Test("Bodies are independent: two together step as each does alone")
    func bodyCount() throws {
        let together = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        let both = try Self.step(together, to: 40, count: 20)
        for (index, body) in Self.bodies.enumerated() {
            let alone = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: [body])
            #expect(Self.bits(try Self.step(alone, to: 40, count: 20)) == Self.bits([both[index]]))
        }
    }

    /// The same bodies from the barycenter, the Sun and Earth: once moved to
    /// the barycenter they are the same, so their states differ by the
    /// origin's.
    @Test("The origin only shifts the states", arguments: [CelestialBody.sun, .earth, .jupiter])
    func origins(origin: CelestialBody) throws {
        let start = Self.time(tt: Self.t0)
        let solarSystem = try Engine.Gravity.SolarSystem(tt: Self.t0)
        let shift = try #require(solarSystem.state(of: origin))
        let barycentric = try Simulation(origin: .solarSystemBarycenter, time: start, states: Self.bodies)
        let relative = try Simulation(
            origin: origin, time: start,
            states: Self.bodies.map {
                Self.state(
                    $0.positionVector - shift.position, $0.velocityVector - shift.velocity, tt: Self.t0)
            })
        let fromBarycenter = try Self.step(barycentric, to: -30, count: 15)
        let fromOrigin = try Self.step(relative, to: -30, count: 15)
        let originNow = try barycentric.state(of: origin)
        for (a, b) in zip(fromBarycenter, fromOrigin) {
            #expect(Self.length(a.positionVector - originNow.positionVector - b.positionVector) <= 1e-13)
            #expect(Self.length(a.velocityVector - originNow.velocityVector - b.velocityVector) <= 1e-17)
        }
    }

    /// The integrator is not exactly reversible: 100 one-day steps out and
    /// back leave the inner body about 2e-9 AU and 5e-11 AU per day from its
    /// start. The gap shrinks at least as the square of the step: half-day steps
    /// leave a quarter of it or less.
    @Test("Stepping forward and then back returns to the start, closer with shorter steps")
    func forwardAndBack() throws {
        func roundTrip(steps: Int) throws -> (position: Double, velocity: Double) {
            let simulation = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
            try Self.step(simulation, to: Self.t0 + 100, count: steps)
            let back = try Self.step(simulation, to: Self.t0, count: steps)
            let gaps = zip(back, Self.bodies).map {
                (Self.length($0.positionVector - $1.positionVector), Self.length($0.velocityVector - $1.velocityVector))
            }
            return (gaps.map(\.0).max() ?? .nan, gaps.map(\.1).max() ?? .nan)
        }
        let daily = try roundTrip(steps: 100)
        let halfDaily = try roundTrip(steps: 200)
        #expect(daily.position <= 1e-8 && daily.velocity <= 2e-10)
        #expect(halfDaily.position * 3.5 < daily.position, "\(daily.position / halfDaily.position)")
    }

    @Test("An update to the current TT steps nothing, copies the current moment and keeps its time")
    func repeatedTime() throws {
        let simulation = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        let first = try simulation.update(to: Self.time(tt: 10))
        let before = simulation.moments.current
        let other = Engine.Time(ut: 9.999, tt: 10, deltaTModel: .jplHorizons)
        let again = try simulation.update(to: other)
        #expect(Self.bits(again) == Self.bits(first))
        #expect(again.allSatisfy { $0.time.ut == 9.999 && $0.time.deltaTModel == .jplHorizons })
        let (current, previous) = simulation.moments
        #expect(Self.bits(current) == Self.bits(before) && Self.bits(previous) == Self.bits(before))
        #expect(simulation.time.ut == 10)
    }

    @Test("An update keeps the caller's time, scales and model")
    func callerTime() throws {
        let simulation = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        let target = Engine.Time(ut: 4.999, tt: 5, deltaTModel: .jplHorizons)
        let states = try simulation.update(to: target)
        #expect(states.allSatisfy { $0.time.ut == 4.999 && $0.time.tt == 5 && $0.time.deltaTModel == .jplHorizons })
        #expect(simulation.time.ut == 4.999 && simulation.time.deltaTModel == .jplHorizons)
        #expect(try simulation.state(of: .mars).time.ut == 4.999)
    }

    // MARK: - Swap

    @Test("A swap after an update undoes it, a second swap redoes it, and a swap before any update changes nothing")
    func swap() throws {
        let simulation = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        let initial = simulation.moments
        simulation.swap()
        #expect(Self.bits(simulation.moments.current) == Self.bits(initial.current))

        let stepped = try simulation.update(to: Self.time(tt: 3))
        let after = simulation.moments
        #expect(Self.bits(after.previous) == Self.bits(initial.current))
        simulation.swap()
        #expect(simulation.time.tt == Self.t0)
        #expect(Self.bits(simulation.moments.current) == Self.bits(initial.current))
        #expect(Self.bits(simulation.moments.previous) == Self.bits(after.current))
        #expect(try simulation.state(of: .jupiter).time.tt == Self.t0)
        simulation.swap()
        #expect(Self.bits(simulation.moments.current) == Self.bits(after.current))
        #expect(Self.bits(try simulation.update(to: Self.time(tt: 3))) == Self.bits(stepped))
    }

    /// The C engine's light-time pattern: step to a trial time, read, swap
    /// back, and try again from the same moment.
    @Test("Swapping back after each trial gives every trial the same start")
    func trials() throws {
        let simulation = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        try simulation.update(to: Self.time(tt: 1))
        var results: [[UInt64]] = []
        for _ in 0..<3 {
            results.append(Self.bits(try simulation.update(to: Self.time(tt: 1.5))))
            simulation.swap()
            #expect(simulation.time.tt == 1)
        }
        #expect(Set(results).count == 1)
        let fresh = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        try fresh.update(to: Self.time(tt: 1))
        #expect(Self.bits(try fresh.update(to: Self.time(tt: 1.5))) == results[0])
    }

    // MARK: - Failure atomicity

    @Test("A rejected update leaves the whole simulation as it was")
    func rejectedUpdate() throws {
        let simulation = try Simulation(origin: .earth, time: Self.time(tt: Self.t0), states: Self.bodies)
        let twin = try Simulation(origin: .earth, time: Self.time(tt: Self.t0), states: Self.bodies)
        try simulation.update(to: Self.time(tt: 2))
        try twin.update(to: Self.time(tt: 2))
        let before = simulation.moments
        for tt in [Double.nan, .infinity, -.infinity, Engine.acceptedTTDays.nextUp, -2e6] {
            #expect(throws: AstronomyError.badTime) { try simulation.update(to: Self.time(tt: tt)) }
            #expect(Self.bits(simulation.moments.current) == Self.bits(before.current))
            #expect(Self.bits(simulation.moments.previous) == Self.bits(before.previous))
        }
        #expect(throws: AstronomyError.badTime) { try simulation.update(to: .invalid) }
        // It carries on as if the rejected calls never happened.
        simulation.swap()
        twin.swap()
        #expect(
            Self.bits(try simulation.update(to: Self.time(tt: 5))) == Self.bits(try twin.update(to: Self.time(tt: 5))))
        #expect(Self.bits(simulation.moments.previous) == Self.bits(twin.moments.previous))
    }

    // MARK: - Bodies' states

    @Test("The Sun and planets come back relative to the origin; other bodies throw invalidBody")
    func bodyStates() throws {
        let simulation = try Simulation(origin: .venus, time: Self.time(tt: Self.t0), states: Self.bodies)
        try simulation.update(to: Self.time(tt: 7))
        let solarSystem = try Engine.Gravity.SolarSystem(tt: 7)
        let venus = try #require(solarSystem.state(of: .venus))
        for body in [CelestialBody.sun, .mercury, .earth, .mars, .jupiter, .saturn, .uranus, .neptune] {
            let state = try simulation.state(of: body)
            let expected = try #require(solarSystem.state(of: body))
            #expect(state.positionVector == expected.position - venus.position, "\(body)")
            #expect(state.velocityVector == expected.velocity - venus.velocity, "\(body)")
        }
        let own = try simulation.state(of: .venus)
        #expect([own.x, own.vx] == [0, 0])
        for body in [CelestialBody.solarSystemBarycenter, .pluto, .moon, .earthMoonBarycenter, .io] {
            #expect(throws: AstronomyError.invalidBody, "\(body)") { _ = try simulation.state(of: body) }
        }
    }

    // MARK: - Threads

    /// Every caller asks for the same time. The first update steps there,
    /// and every later one finds the time already reached, so all of them
    /// return the serial result and the simulation steps exactly once.
    @Test("Simultaneous updates to one time step once and agree with the serial result")
    func concurrentUpdates() throws {
        let serial = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        let expected = Self.bits(try serial.update(to: Self.time(tt: 12)))
        let shared = try Simulation(origin: .sun, time: Self.time(tt: Self.t0), states: Self.bodies)
        let mismatches = EngineBoundedCacheTests.Counter()
        DispatchQueue.concurrentPerform(iterations: 16) { index in
            if index % 4 == 3 {
                _ = try? shared.state(of: .saturn)
                _ = shared.time
                return
            }
            let states = try? shared.update(to: Self.time(tt: 12))
            if states.map(Self.bits) != expected { mismatches.record() }
        }
        #expect(mismatches.count == 0)
        let (current, previous) = shared.moments
        #expect(Self.bits(current) == Self.bits(serial.moments.current))
        // Every update after the first copied the current moment.
        #expect(Self.bits(previous) == Self.bits(current))
    }
}

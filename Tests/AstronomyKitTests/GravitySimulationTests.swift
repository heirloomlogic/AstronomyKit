//
//  GravitySimulationTests.swift
//  AstronomyKit
//
//  Tests for GravitySimulation functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Gravity Simulation Tests")
struct GravitySimulationTests {
    // Helper to create a valid state vector for testing
    private static func makeInitialState(time: AstroTime) throws -> StateVector {
        // Use LagrangePoint to get a valid state vector
        try LagrangePoint.calculate(
            point: .l2,
            at: time,
            majorBody: .sun,
            minorBody: .earth
        )
    }

    // MARK: - Initialization Tests

    @Suite("Initialization")
    struct InitializationTests {
        @Test("Create simulation with valid state vector")
        func createWithValidState() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            #expect(sim.origin == .sun)
            #expect(sim.time == time)
        }

        @Test("Simulation has initial body count")
        func initialBodyCount() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            #expect(sim.bodyCount >= 1)
        }
        @Test("Non-finite initial state throws invalidParameter")
        func nonFiniteInitialStateThrows() {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let bad = StateVector(
                position: Vector3D(x: .nan, y: 0, z: 0, time: time),
                velocity: Vector3D(x: 0, y: 0.01, z: 0, time: time),
                time: time
            )
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try GravitySimulation(origin: .sun, time: time, initialState: bad)
            }
        }

        @Test("Updating a state coincident with origin throws badVector without corrupting simulation")
        func coincidentInitialStateThrowsOnUpdate() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let coincident = StateVector(
                position: Vector3D(x: 0, y: 0, z: 0, time: time),
                velocity: Vector3D(x: 0, y: 0.01, z: 0, time: time),
                time: time
            )
            let sim = try GravitySimulation(origin: .sun, time: time, initialState: coincident)
            #expect(throws: AstronomyError.badVector) {
                try sim.update(to: time.addingDays(1))
            }
            #expect(sim.currentTime() == time)
        }
    }

    // MARK: - Update Tests

    @Suite("Update")
    struct UpdateTests {
        @Test("Update advances simulation time")
        func updateAdvancesTime() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            let newTime = time.addingDays(1)
            try sim.update(to: newTime)

            #expect(sim.time == newTime)
        }

        @Test("Update can move backward in time")
        func updateBackward() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            let pastTime = time.addingDays(-1)
            try sim.update(to: pastTime)

            #expect(sim.time == pastTime)
        }
    }

    // MARK: - State Retrieval Tests

    @Suite("State Retrieval")
    struct StateRetrievalTests {
        @Test("Get body state returns valid vector")
        func getBodyState() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            let state = try sim.state(of: CelestialBody.earth)
            #expect(state.position.magnitude > 0)
        }

        @Test("Current time matches simulation time")
        func currentTimeMatches() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            let currentTime = sim.currentTime()
            #expect(currentTime == time)
        }
    }

    // MARK: - Swap Tests

    @Suite("Swap")
    struct SwapTests {
        @Test("Swap changes simulation direction")
        func swapDirection() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            // Swap should not crash
            sim.swap()

            // Simulation should still be valid
            #expect(sim.bodyCount >= 1)
        }

        @Test("Swap keeps time property synchronized with currentTime")
        func swapUpdatesTime() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            let later = time.addingDays(1)
            try sim.update(to: later)
            #expect(sim.time == later)

            sim.swap()
            #expect(sim.time == later)
            #expect(sim.currentTime() == time)
        }
    }

    // MARK: - Protocol Conformances

    @Suite("Protocol Conformances")
    struct ProtocolConformancesTests {
        @Test("CustomStringConvertible")
        func description() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)
            let initialState = try GravitySimulationTests.makeInitialState(time: time)

            let sim = try GravitySimulation(
                origin: .sun,
                time: time,
                initialState: initialState
            )

            let desc = sim.description

            #expect(desc.contains("GravitySimulation"))
            #expect(desc.contains("sun") || desc.contains("Sun"))
        }
    }
}

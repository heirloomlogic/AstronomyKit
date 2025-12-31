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

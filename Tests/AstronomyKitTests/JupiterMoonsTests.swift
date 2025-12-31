//
//  JupiterMoonsTests.swift
//  AstronomyKit
//
//  Tests for JupiterMoons functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Jupiter Moons Tests")
struct JupiterMoonsTests {

    @Test("Get all four Galilean moons")
    func getAllMoons() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let moons = try Jupiter.moons(at: time)

        // All four moons should have positions
        #expect(moons.io.position.magnitude > 0)
        #expect(moons.europa.position.magnitude > 0)
        #expect(moons.ganymede.position.magnitude > 0)
        #expect(moons.callisto.position.magnitude > 0)
    }

    @Test("Moons are at different distances")
    func moonsAtDifferentDistances() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let moons = try Jupiter.moons(at: time)

        // Io < Europa < Ganymede < Callisto (orbital order)
        // These are orbital semi-major axes in Jupiter radii:
        // Io ~5.9, Europa ~9.4, Ganymede ~15.0, Callisto ~26.4
        // Positions will vary but average distances follow this order
        // Just check they all have different positions
        let positions = [
            moons.io.position,
            moons.europa.position,
            moons.ganymede.position,
            moons.callisto.position,
        ]

        for i in 0..<positions.count {
            for j in (i + 1)..<positions.count {
                #expect(positions[i] != positions[j])
            }
        }
    }

    @Test("Moons have velocities")
    func moonsHaveVelocities() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let moons = try Jupiter.moons(at: time)

        #expect(moons.io.velocity.magnitude > 0)
        #expect(moons.europa.velocity.magnitude > 0)
        #expect(moons.ganymede.velocity.magnitude > 0)
        #expect(moons.callisto.velocity.magnitude > 0)
    }

    @Test("Io moves fastest")
    func ioMovesFastest() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let moons = try Jupiter.moons(at: time)

        // Io has the shortest orbital period, so should have highest velocity
        #expect(moons.io.velocity.magnitude > moons.callisto.velocity.magnitude)
    }

    @Test("Moon positions change over time")
    func positionsChange() throws {
        let time1 = AstroTime(year: 2_025, month: 1, day: 1, hour: 0)
        let time2 = AstroTime(year: 2_025, month: 1, day: 1, hour: 12)

        let moons1 = try Jupiter.moons(at: time1)
        let moons2 = try Jupiter.moons(at: time2)

        // Io has ~42 hour period, so should move noticeably in 12 hours
        #expect(moons1.io.position != moons2.io.position)
    }

    @Test("JupiterMoons is Equatable")
    func equatable() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let moons1 = try Jupiter.moons(at: time)
        let moons2 = try Jupiter.moons(at: time)

        #expect(moons1 == moons2)
    }

    @Test("CustomStringConvertible")
    func description() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let moons = try Jupiter.moons(at: time)

        let desc = moons.description

        #expect(desc.contains("Io"))
        #expect(desc.contains("Europa"))
        #expect(desc.contains("Ganymede"))
        #expect(desc.contains("Callisto"))
    }
}

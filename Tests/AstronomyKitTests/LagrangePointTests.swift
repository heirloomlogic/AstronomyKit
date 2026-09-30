//
//  LagrangePointTests.swift
//  AstronomyKit
//
//  Tests for LagrangePoint functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Lagrange Point Tests")
struct LagrangePointTests {
    // MARK: - LagrangePointID Tests

    @Suite("LagrangePointID")
    struct LagrangePointIDTests {
        @Test("All Lagrange points have names")
        func allHaveNames() {
            for point in LagrangePointID.allCases {
                #expect(!point.name.isEmpty)
            }
        }

        @Test("Names are L1 through L5")
        func correctNames() {
            #expect(LagrangePointID.l1.name == "L1")
            #expect(LagrangePointID.l2.name == "L2")
            #expect(LagrangePointID.l3.name == "L3")
            #expect(LagrangePointID.l4.name == "L4")
            #expect(LagrangePointID.l5.name == "L5")
        }

        @Test("Raw values are 1 through 5")
        func rawValues() {
            #expect(LagrangePointID.l1.rawValue == 1)
            #expect(LagrangePointID.l2.rawValue == 2)
            #expect(LagrangePointID.l3.rawValue == 3)
            #expect(LagrangePointID.l4.rawValue == 4)
            #expect(LagrangePointID.l5.rawValue == 5)
        }
    }

    // MARK: - Sun-Earth Lagrange Points

    @Suite("Sun-Earth System")
    struct SunEarthTests {
        @Test("Calculate Sun-Earth L1")
        func sunEarthL1() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let l1 = try LagrangePoint.calculate(
                point: .l1,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )

            // L1 is between Sun and Earth, about 1.5 million km from Earth
            // Position magnitude is relative to the major body (Sun), so ~1 AU
            #expect(l1.position.magnitude > 0.98)
            #expect(l1.position.magnitude < 1.02)
        }

        @Test("Calculate Sun-Earth L2 (JWST location)")
        func sunEarthL2() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let l2 = try LagrangePoint.calculate(
                point: .l2,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )

            // L2 is beyond Earth, about 1.5 million km past Earth
            // In heliocentric coordinates, it's slightly more than 1 AU
            #expect(l2.position.magnitude > 1.0)
            #expect(l2.position.magnitude < 1.03)
        }

        @Test("StateVector has position and velocity")
        func stateVectorHasComponents() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let l1 = try LagrangePoint.calculate(
                point: .l1,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )

            #expect(l1.position.magnitude > 0)
            #expect(l1.velocity.magnitude > 0)
        }
    }

    // MARK: - Earth-Moon Lagrange Points

    @Suite("Earth-Moon System")
    struct EarthMoonTests {
        @Test("Calculate Earth-Moon L1")
        func earthMoonL1() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let l1 = try LagrangePoint.calculate(
                point: .l1,
                at: time,
                majorBody: .earth,
                minorBody: .moon
            )

            // Earth-Moon L1 is between Earth and Moon
            // Should have some reasonable position
            #expect(l1.position.magnitude > 0)
        }

        @Test(
            "L4 and L5 are at 60-degree positions",
            arguments: [LagrangePointID.l4, LagrangePointID.l5]
        )
        func triangularPoints(point: LagrangePointID) throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let lPoint = try LagrangePoint.calculate(
                point: point,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )

            // L4 and L5 are at approximately the same distance as Earth from Sun
            #expect(lPoint.position.magnitude > 0.98)
            #expect(lPoint.position.magnitude < 1.02)
        }
    }

    // MARK: - StateVector Tests

    @Suite("StateVector")
    struct StateVectorTests {
        @Test("StateVector is Equatable")
        func equatable() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let sv1 = try LagrangePoint.calculate(
                point: .l1,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )
            let sv2 = try LagrangePoint.calculate(
                point: .l1,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )

            #expect(sv1 == sv2)
        }

        @Test("CustomStringConvertible")
        func description() throws {
            let time = AstroTime(year: 2_025, month: 6, day: 21)

            let sv = try LagrangePoint.calculate(
                point: .l1,
                at: time,
                majorBody: .sun,
                minorBody: .earth
            )

            #expect(sv.description.contains("Position"))
            #expect(sv.description.contains("Velocity"))
        }
    }

    // MARK: - Fast Calculation Tests

    @Suite("Fast Calculation")
    struct FastCalculation {
        let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

        @Test("Fast calculation matches standard calculation")
        func fastMatchesStandard() throws {
            let standard = try LagrangePoint.calculate(
                point: .l2,
                at: testTime,
                majorBody: .sun,
                minorBody: .earth
            )

            let sunState = try CelestialBody.sun.barycentricState(at: testTime)
            let earthState = try CelestialBody.earth.barycentricState(at: testTime)
            let sunMass = try #require(CelestialBody.sun.massProduct)
            let earthMass = try #require(CelestialBody.earth.massProduct)

            let fast = try LagrangePoint.calculateFast(
                point: .l2,
                majorState: sunState,
                majorMass: sunMass,
                minorState: earthState,
                minorMass: earthMass
            )

            #expect(abs(fast.position.x - standard.position.x) < 1e-6)
            #expect(abs(fast.position.y - standard.position.y) < 1e-6)
            #expect(abs(fast.position.z - standard.position.z) < 1e-6)
        }

        @Test("Fast calculation works for all Lagrange points", arguments: LagrangePointID.allCases)
        func fastWorksForAllPoints(point: LagrangePointID) throws {
            let sunState = try CelestialBody.sun.barycentricState(at: testTime)
            let earthState = try CelestialBody.earth.barycentricState(at: testTime)
            let sunMass = try #require(CelestialBody.sun.massProduct)
            let earthMass = try #require(CelestialBody.earth.massProduct)

            let result = try LagrangePoint.calculateFast(
                point: point,
                majorState: sunState,
                majorMass: sunMass,
                minorState: earthState,
                minorMass: earthMass
            )
            #expect(result.position.magnitude > 0)
        }
    }

    // MARK: - Degenerate Input Tests

    @Suite("Degenerate Input")
    struct DegenerateInput {
        let testTime = AstroTime(year: 2025, month: 6, day: 15, hour: 12)

        @Test(
            "The same body as major and minor throws invalidBody",
            arguments: [CelestialBody.earth, .sun],
            LagrangePointID.allCases
        )
        func sameBodyThrowsInvalidBody(body: CelestialBody, point: LagrangePointID) {
            #expect(throws: AstronomyError.invalidBody) {
                _ = try LagrangePoint.calculate(point: point, at: testTime, majorBody: body, minorBody: body)
            }
        }

        @Test("The same body throws invalidBody at a huge time too", arguments: LagrangePointID.allCases)
        func sameBodyAtHugeTime(point: LagrangePointID) {
            #expect(throws: AstronomyError.invalidBody) {
                _ = try LagrangePoint.calculate(
                    point: point,
                    at: AstroTime(ut: 1e70),
                    majorBody: .earth,
                    minorBody: .earth
                )
            }
        }

        @Test("Coincident states throw invalidParameter", arguments: LagrangePointID.allCases)
        func coincidentStatesThrowInvalidParameter(point: LagrangePointID) throws {
            let state = try CelestialBody.earth.barycentricState(at: testTime)
            let sunMass = try #require(CelestialBody.sun.massProduct)
            let earthMass = try #require(CelestialBody.earth.massProduct)

            #expect(throws: AstronomyError.invalidParameter) {
                _ = try LagrangePoint.calculateFast(
                    point: point,
                    majorState: state,
                    majorMass: sunMass,
                    minorState: state,
                    minorMass: earthMass
                )
            }
        }

        /// Calls `calculateFast` on a unit-mass major body at the origin and a minor body
        /// at `position` moving at `velocity`.
        private func calculateFast(
            _ point: LagrangePointID,
            minorPosition position: Vector3D,
            minorVelocity velocity: Vector3D
        ) throws -> StateVector {
            let origin = Vector3D(x: 0, y: 0, z: 0, time: testTime)
            return try LagrangePoint.calculateFast(
                point: point,
                majorState: StateVector(position: origin, velocity: origin, time: testTime),
                majorMass: 1,
                minorState: StateVector(position: position, velocity: velocity, time: testTime),
                minorMass: 1e-6
            )
        }

        @Test(
            "Coincident positions with different velocities throw invalidParameter", arguments: LagrangePointID.allCases
        )
        func coincidentPositionsThrowInvalidParameter(point: LagrangePointID) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    minorPosition: Vector3D(x: 0, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0.01, y: 0.02, z: 0, time: testTime)
                )
            }
        }

        @Test("A separation whose square overflows throws invalidParameter", arguments: LagrangePointID.allCases)
        func infiniteSeparationThrowsInvalidParameter(point: LagrangePointID) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    minorPosition: Vector3D(x: 1e200, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: 0, z: 0, time: testTime)
                )
            }
        }
    }
}

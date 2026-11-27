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

        @Test("CaseIterable and Hashable cover all five points")
        func allCasesAndHashable() {
            #expect(LagrangePointID.allCases == [.l1, .l2, .l3, .l4, .l5])
            #expect(Set(LagrangePointID.allCases).count == 5)
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

        /// Calls `calculateFast` on a major body at `majorPosition` (origin by default)
        /// moving at `majorVelocity` (at rest by default) and a minor body at `position`
        /// moving at `velocity`.
        private func calculateFast(
            _ point: LagrangePointID,
            majorPosition: Vector3D? = nil,
            majorVelocity: Vector3D? = nil,
            majorMass: Double = 1,
            minorPosition position: Vector3D,
            minorVelocity velocity: Vector3D,
            minorMass: Double = 1e-6
        ) throws -> StateVector {
            let origin = Vector3D(x: 0, y: 0, z: 0, time: testTime)
            return try LagrangePoint.calculateFast(
                point: point,
                majorState: StateVector(
                    position: majorPosition ?? origin,
                    velocity: majorVelocity ?? origin,
                    time: testTime
                ),
                majorMass: majorMass,
                minorState: StateVector(position: position, velocity: velocity, time: testTime),
                minorMass: minorMass
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

        @Test(
            "A separation that overflows when subtracted throws invalidParameter",
            arguments: LagrangePointID.allCases
        )
        func infiniteSeparationThrowsInvalidParameter(point: LagrangePointID) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    majorPosition: Vector3D(x: -.greatestFiniteMagnitude, y: 0, z: 0, time: testTime),
                    minorPosition: Vector3D(x: .greatestFiniteMagnitude, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime)
                )
            }
        }

        @Test(
            "Non-positive or non-finite masses throw invalidParameter",
            arguments: LagrangePointID.allCases,
            [0.0, -1.0, Double.nan, .infinity, -.infinity]
        )
        func invalidMassThrowsInvalidParameter(point: LagrangePointID, mass: Double) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    majorMass: mass,
                    minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime)
                )
            }
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime),
                    minorMass: mass
                )
            }
        }

        /// A relative velocity that leaves the L4/L5 orbital plane undefined
        /// for a minor body at (1, 0, 0).
        struct TangentCase: Sendable, CustomTestStringConvertible {
            let testDescription: String
            let vx: Double
            let vy: Double
        }

        static let degenerateTangents = [
            TangentCase(testDescription: "zero velocity", vx: 0, vy: 0),
            TangentCase(testDescription: "velocity along the separation", vx: 1, vy: 0),
            TangentCase(testDescription: "velocity against the separation", vx: -0.02, vy: 0),
        ]

        private func calculateFast(_ point: LagrangePointID, tangent: TangentCase) throws -> StateVector {
            try calculateFast(
                point,
                minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: tangent.vx, y: tangent.vy, z: 0, time: testTime)
            )
        }

        @Test(
            "L4 and L5 with a degenerate tangent throw invalidParameter",
            arguments: [LagrangePointID.l4, .l5],
            degenerateTangents
        )
        func degenerateTangentThrowsInvalidParameter(point: LagrangePointID, tangent: TangentCase) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(point, tangent: tangent)
            }
        }

        @Test(
            "L4 and L5 with non-axis-aligned parallel 3D separation and velocity throw invalidParameter",
            arguments: [LagrangePointID.l4, .l5],
            [
                (1.0, 3.0, 9.0, 1.0, 3.0, 9.0),
                (1.0, 3.0, 9.0, -1.0, -3.0, -9.0),
                (1.0, 3.0, 9.0, 3.0, 9.0, 27.0),
                (1.0, 3.0, 9.0, -5.0, -15.0, -45.0),
                (
                    Double(sign: .plus, exponent: 500, significand: 1.0),
                    3.0 * Double(sign: .plus, exponent: 500, significand: 1.0),
                    9.0 * Double(sign: .plus, exponent: 500, significand: 1.0),
                    Double(sign: .plus, exponent: -500, significand: 1.0),
                    3.0 * Double(sign: .plus, exponent: -500, significand: 1.0),
                    9.0 * Double(sign: .plus, exponent: -500, significand: 1.0)
                ),
            ]
        )
        func nonAxisAlignedParallelVelocityThrowsInvalidParameter(
            point: LagrangePointID,
            vectors: (Double, Double, Double, Double, Double, Double)
        ) {
            let (dx, dy, dz, vx, vy, vz) = vectors
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    minorPosition: Vector3D(x: dx, y: dy, z: dz, time: testTime),
                    minorVelocity: Vector3D(x: vx, y: vy, z: vz, time: testTime)
                )
            }
        }

        @Test(
            "L1 to L3 do not use the tangent and still succeed",
            arguments: [LagrangePointID.l1, .l2, .l3],
            degenerateTangents
        )
        func collinearPointsIgnoreTangent(point: LagrangePointID, tangent: TangentCase) throws {
            let state = try calculateFast(point, tangent: tangent)
            let isFinite = [state.position, state.velocity].allSatisfy {
                $0.x.isFinite && $0.y.isFinite && $0.z.isFinite
            }
            #expect(isFinite)
        }

        @Test(
            "L4 and L5 handle extreme tangent velocity scales without underflow or overflow",
            arguments: [LagrangePointID.l4, .l5],
            [1e-200, 1e300]
        )
        func extremeVelocityScalesForTriangularPoints(point: LagrangePointID, vy: Double) throws {
            let state = try calculateFast(
                point,
                minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: 0, y: vy, z: 0, time: testTime)
            )
            let expectedSign = point == .l4 ? 1.0 : -1.0
            let sin60 = 0.8660254037844386
            #expect(abs(state.position.x - 0.5) < 1e-14)
            #expect(abs(state.position.y - expectedSign * sin60) < 1e-14)
            #expect(state.position.z == 0)
            #expect(abs(state.velocity.x - (-expectedSign * sin60 * vy)) <= abs(vy) * 1e-14)
            #expect(abs(state.velocity.y - 0.5 * vy) <= abs(vy) * 1e-14)
            #expect(state.velocity.z == 0)
        }

        @Test(
            "A relative velocity that is not finite throws invalidParameter",
            arguments: LagrangePointID.allCases,
            [Double.nan, .infinity, -.infinity]
        )
        func nonFiniteVelocityThrowsInvalidParameter(point: LagrangePointID, component: Double) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    minorPosition: Vector3D(x: 1, y: 1, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: component, z: 0, time: testTime)
                )
            }
        }

        @Test(
            "A relative velocity that overflows when subtracted throws invalidParameter",
            arguments: LagrangePointID.allCases
        )
        func overflowingVelocityDifferenceThrowsInvalidParameter(point: LagrangePointID) {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    point,
                    majorVelocity: Vector3D(x: 0, y: -.greatestFiniteMagnitude, z: 0, time: testTime),
                    minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: .greatestFiniteMagnitude, z: 0, time: testTime)
                )
            }
        }

        @Test("An L2 velocity that overflows when scaled throws invalidParameter")
        func overflowingScaledVelocityThrowsInvalidParameter() {
            #expect(throws: AstronomyError.invalidParameter) {
                _ = try calculateFast(
                    .l2,
                    minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                    minorVelocity: Vector3D(x: 0, y: .greatestFiniteMagnitude, z: 0, time: testTime)
                )
            }
        }

        @Test(
            "Extreme masses near Double.greatestFiniteMagnitude converge to dimensionless equilibrium",
            arguments: [LagrangePointID.l1, .l2, .l3],
            [(1e308, 1e308), (1e308, 3e302), (Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)]
        )
        func extremeMassesConvergeToEquilibrium(point: LagrangePointID, masses: (Double, Double)) throws {
            let (majorMass, minorMass) = masses
            let state = try calculateFast(
                point,
                majorMass: majorMass,
                minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime),
                minorMass: minorMass
            )
            let u = state.position.x
            #expect(u.isFinite)
            #expect(state.velocity.y.isFinite)

            let scale = max(majorMass, minorMass)
            let m1 = majorMass / scale
            let m2 = minorMass / scale
            let mu = m2 / (m1 + m2)
            let oneMinusMu = m1 / (m1 + m2)

            let c1 = point == .l3 ? oneMinusMu : -oneMinusMu
            let c2 = point == .l2 ? -mu : mu
            let grav1 = c1 / (u * u)
            let grav2 = c2 / ((u - 1.0) * (u - 1.0))
            let residual = abs((u - mu) + grav1 + grav2)
            #expect(residual / (abs(grav1) + abs(grav2)) < 1e-13)
        }

        @Test(
            "Extreme separations succeed without overflow or underflow for all Lagrange points",
            arguments: LagrangePointID.allCases,
            [1e120, 1e150, 1e-120, 1e-150]
        )
        func extremeSeparationsSucceed(point: LagrangePointID, separation: Double) throws {
            let majorMass = 1.0
            let minorMass = 3.0e-6
            let unitRef = try calculateFast(
                point,
                majorMass: majorMass,
                minorPosition: Vector3D(x: 1, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime),
                minorMass: minorMass
            )
            let scaled = try calculateFast(
                point,
                majorMass: majorMass,
                minorPosition: Vector3D(x: separation, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime),
                minorMass: minorMass
            )

            #expect(scaled.position.x.isFinite && scaled.position.y.isFinite && scaled.position.z.isFinite)
            #expect(scaled.velocity.x.isFinite && scaled.velocity.y.isFinite && scaled.velocity.z.isFinite)
            #expect(abs(scaled.position.x / separation - unitRef.position.x) < 1e-14)
            #expect(abs(scaled.position.y / separation - unitRef.position.y) < 1e-14)
            #expect(abs(scaled.position.z / separation - unitRef.position.z) < 1e-14)
            #expect(abs(scaled.velocity.x - unitRef.velocity.x) < 1e-14)
            #expect(abs(scaled.velocity.y - unitRef.velocity.y) < 1e-14)
            #expect(abs(scaled.velocity.z - unitRef.velocity.z) < 1e-14)
        }

        @Test(
            "Off-axis 3D extreme separations preserve vector scaling for all Lagrange points",
            arguments: LagrangePointID.allCases,
            [1e150, 1e-150]
        )
        func offAxisExtremeSeparationsSucceed(point: LagrangePointID, separation: Double) throws {
            let majorMass = 1e308
            let minorMass = 3e302
            let unitRef = try calculateFast(
                point,
                majorMass: majorMass,
                minorPosition: Vector3D(x: 1.0, y: 0.5, z: -0.25, time: testTime),
                minorVelocity: Vector3D(x: 0.002, y: 0.01, z: -0.005, time: testTime),
                minorMass: minorMass
            )
            let scaled = try calculateFast(
                point,
                majorMass: majorMass,
                minorPosition: Vector3D(
                    x: separation,
                    y: 0.5 * separation,
                    z: -0.25 * separation,
                    time: testTime
                ),
                minorVelocity: Vector3D(x: 0.002, y: 0.01, z: -0.005, time: testTime),
                minorMass: minorMass
            )

            #expect(abs(scaled.position.x / separation - unitRef.position.x) < 1e-14)
            #expect(abs(scaled.position.y / separation - unitRef.position.y) < 1e-14)
            #expect(abs(scaled.position.z / separation - unitRef.position.z) < 1e-14)
            #expect(abs(scaled.velocity.x - unitRef.velocity.x) < 1e-14)
            #expect(abs(scaled.velocity.y - unitRef.velocity.y) < 1e-14)
            #expect(abs(scaled.velocity.z - unitRef.velocity.z) < 1e-14)
        }

        @Test(
            "Solar-system L1 to L5 match physical equilibrium and geometry",
            arguments: LagrangePointID.allCases
        )
        func solarSystemParityAndEquilibrium(point: LagrangePointID) throws {
            let sunMass = try #require(CelestialBody.sun.massProduct)
            let earthMass = try #require(CelestialBody.earth.massProduct)
            let sunState = try CelestialBody.sun.barycentricState(at: testTime)
            let earthState = try CelestialBody.earth.barycentricState(at: testTime)
            let result = try LagrangePoint.calculateFast(
                point: point,
                majorState: sunState,
                majorMass: sunMass,
                minorState: earthState,
                minorMass: earthMass
            )

            let dx = earthState.position.x - sunState.position.x
            let dy = earthState.position.y - sunState.position.y
            let dz = earthState.position.z - sunState.position.z
            let dist = (dx * dx + dy * dy + dz * dz).squareRoot()

            if point == .l4 || point == .l5 {
                let pMag = result.position.magnitude
                let diffX = result.position.x - dx
                let diffY = result.position.y - dy
                let diffZ = result.position.z - dz
                let minorDist = (diffX * diffX + diffY * diffY + diffZ * diffZ).squareRoot()
                #expect(abs(pMag - dist) / dist < 1e-14)
                #expect(abs(minorDist - dist) / dist < 1e-14)
            } else {
                let u = (result.position.x * dx + result.position.y * dy + result.position.z * dz) / (dist * dist)
                #expect(abs(result.position.x - u * dx) < 1e-14)
                #expect(abs(result.position.y - u * dy) < 1e-14)
                #expect(abs(result.position.z - u * dz) < 1e-14)

                let total = sunMass + earthMass
                let mu = earthMass / total
                let oneMinusMu = sunMass / total
                let c1 = point == .l3 ? oneMinusMu : -oneMinusMu
                let c2 = point == .l2 ? -mu : mu
                let grav1 = c1 / (u * u)
                let grav2 = c2 / ((u - 1.0) * (u - 1.0))
                let residual = abs((u - mu) + grav1 + grav2)
                #expect(residual / (abs(grav1) + abs(grav2)) < 1e-13)
            }
        }

        @Test(
            "L3 converges to physical equilibrium for similar masses",
            arguments: [
                (1.431350589334418e-08, 1.1985515525262112e-08, 0.00028200563538926415),
                (31.0, 12.0, 1.0),
                (1.0, 0.5067, 1.0),
            ]
        )
        func similarMassL3ConvergesToEquilibrium(majorMass: Double, minorMass: Double, separation: Double) throws {
            let state = try calculateFast(
                .l3,
                majorMass: majorMass,
                minorPosition: Vector3D(x: separation, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime),
                minorMass: minorMass
            )
            let x = state.position.x
            #expect(x.isFinite && x < 0)
            let xcm = separation * minorMass / (majorMass + minorMass)
            let omega2 = (majorMass + minorMass) / (separation * separation * separation)
            let grav1 = majorMass / (x * x)
            let grav2 = minorMass / ((separation - x) * (separation - x))
            let residual = abs(omega2 * (x - xcm) + grav1 + grav2)
            #expect(residual / (grav1 + grav2) < 1e-11)
        }

        @Test("L1 converges to physical equilibrium near mu = 1/(1+sqrt(24))")
        func criticalMassRatioL1Converges() throws {
            let majorMass = 24.0.squareRoot()
            let minorMass = 1.0
            let separation = 1.0
            let state = try calculateFast(
                .l1,
                majorMass: majorMass,
                minorPosition: Vector3D(x: separation, y: 0, z: 0, time: testTime),
                minorVelocity: Vector3D(x: 0, y: 0.01, z: 0, time: testTime),
                minorMass: minorMass
            )
            let x = state.position.x
            #expect(x.isFinite && x > 0 && x < separation)
            let xcm = separation * minorMass / (majorMass + minorMass)
            let omega2 = (majorMass + minorMass) / (separation * separation * separation)
            let grav1 = majorMass / (x * x)
            let grav2 = minorMass / ((separation - x) * (separation - x))
            let residual = abs(omega2 * (x - xcm) - grav1 + grav2)
            #expect(residual / (grav1 + grav2) < 1e-11)
        }
    }
}

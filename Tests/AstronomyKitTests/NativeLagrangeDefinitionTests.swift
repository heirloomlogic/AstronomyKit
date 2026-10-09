import Foundation
import Testing

@testable import AstronomyKit

@Suite("Lagrange definition checks")
struct NativeLagrangeDefinitionTests {
    @Test(
        "Collinear points balance gravity and centrifugal acceleration", arguments: [1e-6, 0.001, 0.01],
        [LagrangePointID.l1, .l2, .l3])
    func equilibrium(ratio: Double, point: LagrangePointID) throws {
        let time = Engine.Time(ut: 0, deltaTModel: .espenakMeeus)
        let major = Engine.State<Engine.EQJ>(x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, time: time)
        let minor = Engine.State<Engine.EQJ>(x: 1, y: 0, z: 0, vx: 0, vy: sqrt(1 + ratio), vz: 0, time: time)
        let result = try Engine.Lagrange.calculateFast(
            point: point, majorState: major, majorMass: 1, minorState: minor, minorMass: ratio)
        let x = result.x
        let residual =
            (1 + ratio) * (x - ratio / (1 + ratio)) - x / pow(abs(x), 3) - ratio * (x - 1) / pow(abs(x - 1), 3)
        #expect(abs(residual) < 1e-11)
        #expect(result.y == 0 && result.z == 0)
        #expect(abs(result.vy - x * sqrt(1 + ratio)) < 1e-14)
        switch point {
        case .l1: #expect(x > 0 && x < 1)
        case .l2: #expect(x > 1)
        case .l3: #expect(x < 0)
        default: Issue.record("Unexpected triangular point")
        }
    }

    @Test(
        "L4 and L5 form equilateral triangles over stratified dates", arguments: [1_900, 2_000, 2_050, 2_130],
        [LagrangePointID.l4, .l5])
    func equilateral(year: Int, point: LagrangePointID) throws {
        let time = AstroTime(year: year, month: 6, day: 21)
        let earth = try CelestialBody.earth.heliocentricState(at: time)
        let result = try LagrangePoint.calculate(point: point, at: time, majorBody: .sun, minorBody: .earth)
        let r = earth.position.magnitude
        let d = sqrt(
            pow(result.position.x - earth.position.x, 2) + pow(result.position.y - earth.position.y, 2)
                + pow(result.position.z - earth.position.z, 2))
        #expect(abs(result.position.magnitude - r) < 1e-14)
        #expect(abs(d - r) < 1e-14)
        #expect(
            abs(
                result.position.x * earth.position.x + result.position.y * earth.position.y + result.position.z
                    * earth.position.z - 0.5 * r * r) < 1e-14)
    }

    // NASA's SOHO orbit and Webb orbit pages give about 1.5 million km for Sun-Earth L1/L2.
    // https://soho.nascom.nasa.gov/about/orbit.html
    // https://science.nasa.gov/mission/webb/orbit/
    @Test(
        "Sun-Earth L1 and L2 retain the published approximate distance", arguments: [1_900, 2_000, 2_050, 2_130],
        [LagrangePointID.l1, .l2])
    func publishedDistance(year: Int, point: LagrangePointID) throws {
        let time = AstroTime(year: year, month: 6, day: 21)
        let earth = try CelestialBody.earth.heliocentricPosition(at: time)
        let result = try LagrangePoint.calculate(point: point, at: time, majorBody: .sun, minorBody: .earth).position
        let distance =
            sqrt(pow(result.x - earth.x, 2) + pow(result.y - earth.y, 2) + pow(result.z - earth.z, 2)) * 149_597_870.7
        #expect(abs(distance - 1_500_000) < 50_000)
    }
}

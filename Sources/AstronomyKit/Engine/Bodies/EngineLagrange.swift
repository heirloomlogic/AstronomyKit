import Foundation

extension Engine {
    /// Instantaneous restricted three-body equilibria, relative to the major body.
    enum Lagrange {}
}

extension Engine.Gravity {
    /// The pinned engine's GM values in AU³/day²; the Moon uses its Earth mass ratio.
    static func massProduct(of body: CelestialBody) -> Double? {
        switch body {
        case .sun: sunGM
        case .mercury: mercuryGM
        case .venus: venusGM
        case .earth: earthGM
        case .moon: earthGM / Engine.Moon.earthMoonMassRatio
        case .earthMoonBarycenter: earthGM + earthGM / Engine.Moon.earthMoonMassRatio
        case .mars: marsGM
        case .jupiter: jupiterGM
        case .saturn: saturnGM
        case .uranus: uranusGM
        case .neptune: neptuneGM
        case .pluto: 0.2188699765425970e-11
        default: nil
        }
    }
}

extension Engine.Lagrange {
    static func calculate(
        point: LagrangePointID, at time: Engine.Time, majorBody: CelestialBody, minorBody: CelestialBody
    ) throws -> Engine.State<Engine.EQJ> {
        guard let majorMass = Engine.Gravity.massProduct(of: majorBody),
            let minorMass = Engine.Gravity.massProduct(of: minorBody), majorBody != minorBody
        else { throw AstronomyError.invalidBody }
        let major: Engine.State<Engine.EQJ>
        let minor: Engine.State<Engine.EQJ>
        if majorBody == .earth && minorBody == .moon {
            major = Engine.State(x: 0, y: 0, z: 0, vx: 0, vy: 0, vz: 0, time: time)
            minor = try Engine.Moon.geocentricState(at: time)
        } else {
            major = try Engine.Positions.heliocentricState(of: majorBody, at: time)
            minor = try Engine.Positions.heliocentricState(of: minorBody, at: time)
        }
        do {
            return try calculateFast(
                point: point, majorState: major, majorMass: majorMass, minorState: minor, minorMass: minorMass)
        } catch AstronomyError.invalidParameter {
            // With valid distinct bodies, rejected states came from the requested time.
            throw AstronomyError.badTime
        }
    }

    /// Ports the existing bounded Newton and orbital-plane construction, including its error ordering.
    static func calculateFast(
        point: LagrangePointID, majorState: Engine.State<Engine.EQJ>, majorMass: Double,
        minorState: Engine.State<Engine.EQJ>, minorMass: Double
    ) throws -> Engine.State<Engine.EQJ> {
        guard majorMass.isFinite, majorMass > 0, minorMass.isFinite, minorMass > 0 else {
            throw AstronomyError.invalidParameter
        }
        let displacement = minorState.positionVector - majorState.positionVector
        let velocity = minorState.velocityVector - majorState.velocityVector
        let squaredDistance = dot(displacement, displacement)
        guard squaredDistance != 0, squaredDistance.isFinite else { throw AstronomyError.invalidParameter }
        let distance = sqrt(squaredDistance)
        let position: SIMD3<Double>
        let speed: SIMD3<Double>
        if point == .l4 || point == .l5 {
            let normal = cross(displacement, velocity)
            let tangent = cross(normal, displacement)
            let length = sqrt(dot(tangent, tangent))
            guard length != 0, length.isFinite else { throw AstronomyError.invalidParameter }
            let u = tangent / length
            let d = displacement / distance
            let sine = point == .l4 ? 0.8660254037844386 : -0.8660254037844386
            let radial = 0.5 * d + sine * u
            let rotatedTangent = 0.5 * u - sine * d
            position = distance * radial
            speed = dot(velocity, d) * radial + dot(velocity, u) * rotatedTangent
        } else {
            let total = majorMass + minorMass
            let r1 = -distance * (minorMass / total)
            let r2 = distance * (majorMass / total)
            let omegaSquared = total / (squaredDistance * distance)
            let initialScale: Double
            let numerator1: Double
            let numerator2: Double
            if point == .l1 || point == .l2 {
                let offset = (majorMass / total) * cbrt(minorMass / (3 * majorMass))
                initialScale = point == .l1 ? 1 - offset : 1 + offset
                numerator1 = -majorMass
                numerator2 = point == .l1 ? minorMass : -minorMass
            } else {
                initialScale = ((7.0 / 12.0) * minorMass - majorMass) / (minorMass + majorMass)
                numerator1 = majorMass
                numerator2 = minorMass
            }
            var x = distance * initialScale - r1
            var iterations = 0
            var correction: Double
            repeat {
                iterations += 1
                guard iterations <= 10_000 else { throw AstronomyError.noConvergence }
                let dr1 = x - r1
                let dr2 = x - r2
                let acceleration = omegaSquared * x + numerator1 / (dr1 * dr1) + numerator2 / (dr2 * dr2)
                let derivative = omegaSquared - 2 * numerator1 / (dr1 * dr1 * dr1) - 2 * numerator2 / (dr2 * dr2 * dr2)
                correction = acceleration / derivative
                x -= correction
            } while abs(correction / distance) > 1e-14
            let scale = (x - r1) / distance
            position = scale * displacement
            speed = scale * velocity
        }
        guard [position.x, position.y, position.z, speed.x, speed.y, speed.z].allSatisfy(\.isFinite) else {
            throw AstronomyError.invalidParameter
        }
        return Engine.State(position: position, velocity: speed, time: majorState.time)
    }

    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
    }
}

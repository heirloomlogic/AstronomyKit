//
//  EngineLagrangePoint.swift
//  AstronomyKit
//
//  Pure-Swift implementation of Lagrange points L1-L5 matching Astronomy_LagrangePoint
//  and Astronomy_LagrangePointFast (including degenerate-input and iteration guards).
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineLagrangePoint {
    static func calculate(
        point: LagrangePointID,
        at time: AstroTime,
        majorBody: CelestialBody,
        minorBody: CelestialBody
    ) throws -> StateVector {
        let majorMass = EngineMath.massProduct(of: majorBody)
        guard majorMass > 0.0 else {
            throw AstronomyError.invalidBody
        }

        let minorMass = EngineMath.massProduct(of: minorBody)
        guard minorMass > 0.0 else {
            throw AstronomyError.invalidBody
        }

        guard majorBody != minorBody else {
            throw AstronomyError.invalidBody
        }

        let majorState: StateVector
        let minorState: StateVector

        if majorBody == .earth && minorBody == .moon {
            let zero = Vector3D(x: 0.0, y: 0.0, z: 0.0, time: time)
            majorState = StateVector(position: zero, velocity: zero, time: time)
            minorState = try EnginePositions.geoMoonState(at: time)
        } else {
            majorState = try EnginePositions.helioState(of: majorBody, at: time)
            minorState = try EnginePositions.helioState(of: minorBody, at: time)
        }

        return try calculateFast(
            point: point,
            majorState: majorState,
            majorMass: majorMass,
            minorState: minorState,
            minorMass: minorMass
        )
    }

    static func calculateFast(
        point: LagrangePointID,
        majorState: StateVector,
        majorMass: Double,
        minorState: StateVector,
        minorMass: Double
    ) throws -> StateVector {
        let cos60 = 0.5
        let sin60 = 0.8660254037844386
        let iterLimit = 10_000

        guard majorMass.isFinite, majorMass > 0.0, minorMass.isFinite, minorMass > 0.0 else {
            throw AstronomyError.invalidParameter
        }

        let dx = minorState.position.x - majorState.position.x
        let dy = minorState.position.y - majorState.position.y
        let dz = minorState.position.z - majorState.position.z
        guard dx.isFinite, dy.isFinite, dz.isFinite else {
            throw AstronomyError.invalidParameter
        }

        let dScale = max(abs(dx), max(abs(dy), abs(dz)))
        guard dScale > 0.0 else {
            throw AstronomyError.invalidParameter
        }

        let vx = minorState.velocity.x - majorState.velocity.x
        let vy = minorState.velocity.y - majorState.velocity.y
        let vz = minorState.velocity.z - majorState.velocity.z
        guard vx.isFinite, vy.isFinite, vz.isFinite else {
            throw AstronomyError.invalidParameter
        }

        let px: Double
        let py: Double
        let pz: Double
        let pvx: Double
        let pvy: Double
        let pvz: Double

        if point == .l4 || point == .l5 {
            let sdx = dx / dScale
            let sdy = dy / dScale
            let sdz = dz / dScale
            let sLen = sqrt(sdx * sdx + sdy * sdy + sdz * sdz)
            let invSLen = 1.0 / sLen
            let rx = sdx * invSLen
            let ry = sdy * invSLen
            let rz = sdz * invSLen

            let vScale = max(abs(vx), max(abs(vy), abs(vz)))
            guard vScale > 0.0 else {
                throw AstronomyError.invalidParameter
            }
            let svx = vx / vScale
            let svy = vy / vScale
            let svz = vz / vScale

            // Cross infinity-norm-scaled vectors directly before dividing by sLen
            // so parallel 3D separation and velocity vectors cancel to exact zero
            // instead of leaving 1-ULP rounding asymmetry.
            let nx = sdy * svz - sdz * svy
            let ny = sdz * svx - sdx * svz
            let nz = sdx * svy - sdy * svx

            let rawUx = ny * sdz - nz * sdy
            let rawUy = nz * sdx - nx * sdz
            let rawUz = nx * sdy - ny * sdx
            let u2 = rawUx * rawUx + rawUy * rawUy + rawUz * rawUz
            let ux: Double
            let uy: Double
            let uz: Double
            if u2 >= Double.leastNormalMagnitude {
                let invULen = 1.0 / sqrt(u2)
                ux = rawUx * invULen
                uy = rawUy * invULen
                uz = rawUz * invULen
            } else {
                let uScale = max(abs(rawUx), max(abs(rawUy), abs(rawUz)))
                guard uScale > 0.0 else {
                    throw AstronomyError.invalidParameter
                }
                let sux = rawUx / uScale
                let suy = rawUy / uScale
                let suz = rawUz / uScale
                let invULen = 1.0 / sqrt(sux * sux + suy * suy + suz * suz)
                ux = sux * invULen
                uy = suy * invULen
                uz = suz * invULen
            }

            let vert = (point == .l4) ? sin60 : -sin60
            let rotDx = cos60 * rx + vert * ux
            let rotDy = cos60 * ry + vert * uy
            let rotDz = cos60 * rz + vert * uz

            let rotUx = cos60 * ux - vert * rx
            let rotUy = cos60 * uy - vert * ry
            let rotUz = cos60 * uz - vert * rz

            px = dScale * (sLen * rotDx)
            py = dScale * (sLen * rotDy)
            pz = dScale * (sLen * rotDz)

            let svrad = svx * rx + svy * ry + svz * rz
            let svtan = svx * ux + svy * uy + svz * uz
            pvx = vScale * (svrad * rotDx + svtan * rotUx)
            pvy = vScale * (svrad * rotDy + svtan * rotUy)
            pvz = vScale * (svrad * rotDz + svtan * rotUz)
        } else {
            // Solve L1-L3 in dimensionless coordinate u = (x - r1) / dist and mass
            // fraction mu = minorMass / (majorMass + minorMass), avoiding overflow
            // or underflow of totalMass, dist^2, and dr^3 at extreme scales.
            let mScale = max(majorMass, minorMass)
            let m1 = majorMass / mScale
            let m2 = minorMass / mScale
            let mSum = m1 + m2
            let mu = m2 / mSum
            let oneMinusMu = m1 / mSum

            var u: Double
            let c1: Double
            let c2: Double
            if point == .l1 || point == .l2 {
                let offset = oneMinusMu * cbrt(m2 / (3.0 * m1))
                c1 = -oneMinusMu
                if point == .l1 {
                    u = 1.0 - offset
                    c2 = mu
                } else {
                    u = 1.0 + offset
                    c2 = -mu
                }
            } else {
                u = (7.0 / 12.0) * mu - oneMinusMu
                c1 = oneMinusMu
                c2 = mu
            }

            var iter = 0
            var deltaU: Double
            repeat {
                iter &+= 1
                if iter > iterLimit {
                    throw AstronomyError.noConvergence
                }
                let dr1 = u
                let dr2 = u - 1.0
                let term1 = c1 / (dr1 * dr1)
                let term2 = c2 / (dr2 * dr2)
                let accel = (u - mu) + term1 + term2
                let deriv = 1.0 - 2.0 * (term1 / dr1 + term2 / dr2)
                deltaU = accel / deriv
                u -= deltaU
            } while abs(deltaU) > 1.0e-14

            px = u * dx
            py = u * dy
            pz = u * dz
            pvx = u * vx
            pvy = u * vy
            pvz = u * vz
        }

        guard px.isFinite, py.isFinite, pz.isFinite, pvx.isFinite, pvy.isFinite, pvz.isFinite else {
            throw AstronomyError.invalidParameter
        }

        let t = majorState.time
        return StateVector(
            position: Vector3D(x: px, y: py, z: pz, time: t),
            velocity: Vector3D(x: pvx, y: pvy, z: pvz, time: t),
            time: t
        )
    }
}

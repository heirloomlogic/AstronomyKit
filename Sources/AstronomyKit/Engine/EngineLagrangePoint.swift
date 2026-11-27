//
//  EngineLagrangePoint.swift
//  AstronomyKit
//
//  Pure-Swift implementation of Lagrange points L1-L5 matching Astronomy_LagrangePoint
//  and Astronomy_LagrangePointFast (including degenerate-input and iteration guards).
//

import CLibAstronomy

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
        let majorMass = Astronomy_MassProduct(majorBody.raw)
        guard majorMass > 0.0 else {
            throw AstronomyError.invalidBody
        }

        let minorMass = Astronomy_MassProduct(minorBody.raw)
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
            minorState = try StateVector(Astronomy_GeoMoonState(time.raw))
        } else {
            majorState = try StateVector(Astronomy_HelioState(majorBody.raw, time.raw))
            minorState = try StateVector(Astronomy_HelioState(minorBody.raw, time.raw))
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

        var dx = minorState.position.x - majorState.position.x
        var dy = minorState.position.y - majorState.position.y
        var dz = minorState.position.z - majorState.position.z
        let r2 = dx * dx + dy * dy + dz * dz
        guard r2 != 0.0, r2.isFinite else {
            throw AstronomyError.invalidParameter
        }

        let dist = sqrt(r2)
        let vx = minorState.velocity.x - majorState.velocity.x
        let vy = minorState.velocity.y - majorState.velocity.y
        let vz = minorState.velocity.z - majorState.velocity.z

        let px: Double
        let py: Double
        let pz: Double
        let pvx: Double
        let pvy: Double
        let pvz: Double

        if point == .l4 || point == .l5 {
            let nx = dy * vz - dz * vy
            let ny = dz * vx - dx * vz
            let nz = dx * vy - dy * vx

            var ux = ny * dz - nz * dy
            var uy = nz * dx - nx * dz
            var uz = nx * dy - ny * dx
            let uLen = sqrt(ux * ux + uy * uy + uz * uz)
            guard uLen != 0.0, uLen.isFinite else {
                throw AstronomyError.invalidParameter
            }

            ux /= uLen
            uy /= uLen
            uz /= uLen

            dx /= dist
            dy /= dist
            dz /= dist

            let vert = (point == .l4) ? sin60 : -sin60
            let rotDx = cos60 * dx + vert * ux
            let rotDy = cos60 * dy + vert * uy
            let rotDz = cos60 * dz + vert * uz

            let rotUx = cos60 * ux - vert * dx
            let rotUy = cos60 * uy - vert * dy
            let rotUz = cos60 * uz - vert * dz

            px = dist * rotDx
            py = dist * rotDy
            pz = dist * rotDz

            let vrad = vx * dx + vy * dy + vz * dz
            let vtan = vx * ux + vy * uy + vz * uz
            pvx = vrad * rotDx + vtan * rotUx
            pvy = vrad * rotDy + vtan * rotUy
            pvz = vrad * rotDz + vtan * rotUz
        } else {
            let totalMass = majorMass + minorMass
            let r1 = -dist * (minorMass / totalMass)
            let r2Bary = dist * (majorMass / totalMass)
            let omega2 = totalMass / (r2 * dist)

            var scale: Double
            let numer1: Double
            let numer2: Double
            if point == .l1 || point == .l2 {
                scale = (majorMass / totalMass) * cbrt(minorMass / (3.0 * majorMass))
                numer1 = -majorMass
                if point == .l1 {
                    scale = 1.0 - scale
                    numer2 = minorMass
                } else {
                    scale = 1.0 + scale
                    numer2 = -minorMass
                }
            } else {
                scale = ((7.0 / 12.0) * minorMass - majorMass) / totalMass
                numer1 = majorMass
                numer2 = minorMass
            }

            var x = dist * scale + r1
            var iter = 0
            var deltaX: Double
            repeat {
                iter &+= 1
                if iter > iterLimit {
                    throw AstronomyError.noConvergence
                }
                let dr1 = x - r1
                let dr2 = x - r2Bary
                let accel = omega2 * x + numer1 / (dr1 * dr1) + numer2 / (dr2 * dr2)
                let deriv = omega2 - 2.0 * numer1 / (dr1 * dr1 * dr1) - 2.0 * numer2 / (dr2 * dr2 * dr2)
                deltaX = accel / deriv
                x -= deltaX
            } while abs(deltaX / dist) > 1.0e-14

            scale = (x - r1) / dist
            px = scale * dx
            py = scale * dy
            pz = scale * dz
            pvx = scale * vx
            pvy = scale * vy
            pvz = scale * vz
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

import Foundation

extension Engine.Shadows {
    typealias Triple = SIMD3<Double>

    static func dot(_ a: Triple, _ b: Triple) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
    static func norm(_ a: Triple) -> Double { hypot(hypot(a.x, a.y), a.z) }
    static func finite(_ a: Triple) -> Bool { a.x.isFinite && a.y.isFinite && a.z.isFinite }

    static var earthRadii: Triple {
        let r = Engine.Observers.equatorialRadiusKilometers
        return Triple(r, r, r * Engine.Observers.polarRatio)
    }

    /// Near forward intersection with an ellipsoid. The tangent is an intersection; an axis miss is nil.
    static func axisIntersection(origin: Triple, direction: Triple, radii: Triple) throws -> Triple? {
        guard finite(origin), finite(direction), finite(radii), radii.min() > 0 else {
            throw AstronomyError.badVector
        }
        let scaledOrigin = origin / radii
        let scaledDirection = direction / radii
        let length = norm(scaledDirection)
        guard length > 0, length.isFinite, finite(scaledOrigin) else { throw AstronomyError.badVector }
        let unit = scaledDirection / length
        let along = dot(scaledOrigin, unit)
        let closest = scaledOrigin - along * unit
        let distance = norm(closest)
        guard along.isFinite, distance.isFinite else { throw AstronomyError.badVector }
        guard distance <= 1 else { return nil }
        let halfChord = sqrt((1 - distance) * (1 + distance))
        var step = -along - halfChord
        if step < 0 { step = -along + halfChord }
        guard step >= 0 else { return nil }
        let result = (closest + (along + step) * unit) * radii
        guard finite(result) else { throw AstronomyError.badVector }
        return result
    }

    /// Closest point on the ellipsoid to a line that misses it, in ordinary kilometers.
    static func closestPointToMissedAxis(origin: Triple, direction: Triple, radii: Triple) throws -> Triple {
        guard finite(origin), finite(direction), finite(radii), radii.min() > 0 else {
            throw AstronomyError.badVector
        }
        let length = norm(direction)
        guard length > 0, length.isFinite else { throw AstronomyError.badVector }
        let unit = direction / length
        let perpendicular = origin - dot(origin, unit) * unit
        let v = radii * unit
        let b = radii * perpendicular
        let squared = radii * radii
        guard finite(b), finite(squared) else { throw AstronomyError.badVector }
        // The multiplier is positive for a missed axis. Sherman-Morrison solves the diagonal-minus-rank-one system.
        func point(_ lambda: Double) -> Triple {
            let diagonal = squared + Triple(repeating: lambda)
            let z = b / diagonal
            let w = v / diagonal
            let denominator = 1 - dot(v, w)
            return z + w * (dot(v, z) / denominator)
        }
        var upper = squared.max()
        for _ in 0..<128 {
            let p = point(upper)
            if finite(p), norm(p) <= 1 { break }
            upper *= 2
            guard upper.isFinite else { throw AstronomyError.badVector }
        }
        var lower = 0.0
        var result = point(upper)
        for _ in 0..<128 {
            let middle = lower + (upper - lower) / 2
            if middle == lower || middle == upper { break }
            let p = point(middle)
            if !finite(p) || norm(p) > 1 {
                lower = middle
            } else {
                upper = middle
                result = p
            }
        }
        let size = norm(result)
        guard size > 0, size.isFinite else { throw AstronomyError.searchFailure }
        return radii * (result / size)
    }

    /// Finds a surface point inside one branch of a finite cone, or proves that the ellipsoid misses it.
    /// Convex supporting planes bound distance-to-axis minus the linear cone radius over the solid ellipsoid.
    static func coneSurfacePoint(
        origin: Triple, unit: Triple, radiusAtOrigin: Double, slope: Double, radii: Triple, seed: Triple
    ) throws -> Triple? {
        guard finite(origin), finite(unit), finite(radii), finite(seed), radii.min() > 0,
            radiusAtOrigin.isFinite, slope.isFinite,
            abs(norm(unit) - 1) <= 4 * Double.ulpOfOne,
            norm(seed / radii) <= 1 + 8 * Double.ulpOfOne
        else { throw AstronomyError.badVector }
        func evaluate(_ p: Triple) throws -> (Double, Triple) {
            let d = p - origin
            let along = dot(d, unit)
            let perpendicular = d - along * unit
            let distance = norm(perpendicular)
            guard distance > 0, distance.isFinite else { throw AstronomyError.searchFailure }
            let value = distance - radiusAtOrigin - slope * along
            let gradient = perpendicular / distance - slope * unit
            guard value.isFinite, finite(gradient) else { throw AstronomyError.badVector }
            return (value, gradient)
        }
        var point = seed
        for _ in 0..<256 {
            let (value, gradient) = try evaluate(point)
            if value <= 0, abs(norm(point / radii) - 1) <= 8 * Double.ulpOfOne { return point }
            let scaled = radii * gradient
            let length = norm(scaled)
            guard length > 0, length.isFinite else { throw AstronomyError.searchFailure }
            let support = -radii * scaled / length
            let bound = value + dot(gradient, support - point)
            if bound > 0 { return nil }
            if try evaluate(support).0 <= 0 { return support }
            // Minimize this convex function on the feasible segment; every iterate remains inside the ellipsoid.
            let direction = support - point
            var low = 0.0
            var high = 1.0
            for _ in 0..<56 {
                let middle = (low + high) / 2
                let derivative = dot(try evaluate(point + middle * direction).1, direction)
                if derivative < 0 { low = middle } else { high = middle }
            }
            let next = point + ((low + high) / 2) * direction
            if next == point { break }
            point = next
            // A negative interior value alone does not establish the requested surface result.
        }
        throw AstronomyError.searchFailure
    }
}

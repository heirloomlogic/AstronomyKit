//
//  EngineShadowGeometry.swift
//  AstronomyKit
//
//  Shared native conical-shadow and disc-overlap geometry.
//

import Foundation

extension Engine {
    enum Shadows {}
}

extension Engine.Shadows {
    struct Shadow<F: Engine.Frame>: Sendable {
        let time: Engine.Time
        let axisFraction: Double
        let axisDistanceKilometers: Double
        let umbraRadiusKilometers: Double
        let penumbraRadiusKilometers: Double
        let target: Engine.Vector<F>
        let direction: Engine.Vector<F>
    }

    static func calculate<F>(
        bodyRadiusKilometers: Double,
        target: Engine.Vector<F>,
        direction: Engine.Vector<F>
    ) throws -> Shadow<F> {
        guard bodyRadiusKilometers > 0, bodyRadiusKilometers.isFinite else {
            throw AstronomyError.invalidParameter
        }
        let directionSquared = direction.x * direction.x + direction.y * direction.y + direction.z * direction.z
        guard directionSquared > 0, directionSquared.isFinite else { throw AstronomyError.badVector }
        let axisFraction = (direction.x * target.x + direction.y * target.y + direction.z * target.z) / directionSquared
        let dx = axisFraction * direction.x - target.x
        let dy = axisFraction * direction.y - target.y
        let dz = axisFraction * direction.z - target.z
        let axisDistanceKilometers = Engine.kilometersPerAU * (dx * dx + dy * dy + dz * dz).squareRoot()
        let umbraRadiusKilometers =
            sunRadiusKilometers - (1 + axisFraction) * (sunRadiusKilometers - bodyRadiusKilometers)
        let penumbraRadiusKilometers =
            -sunRadiusKilometers + (1 + axisFraction) * (sunRadiusKilometers + bodyRadiusKilometers)
        guard axisFraction.isFinite, axisDistanceKilometers.isFinite, umbraRadiusKilometers.isFinite,
            penumbraRadiusKilometers.isFinite
        else {
            throw AstronomyError.badTime
        }
        return Shadow(
            time: target.time, axisFraction: axisFraction, axisDistanceKilometers: axisDistanceKilometers,
            umbraRadiusKilometers: umbraRadiusKilometers, penumbraRadiusKilometers: penumbraRadiusKilometers,
            target: target, direction: direction)
    }

    /// Earth's lunar-eclipse shadows using the Danjon convention adopted by NASA's Five Millennium Canon.
    static func lunarEarthShadow<F>(
        target: Engine.Vector<F>,
        direction: Engine.Vector<F>
    ) throws -> Shadow<F> {
        let geometric = try calculate(
            bodyRadiusKilometers: Engine.Observers.equatorialRadiusKilometers,
            target: target,
            direction: direction)
        let targetDistance = target.length * Engine.kilometersPerAU
        let directionDistance = direction.length * Engine.kilometersPerAU
        let earthRadius = Engine.Observers.equatorialRadiusKilometers
        guard targetDistance > earthRadius, directionDistance > sunRadiusKilometers else {
            throw AstronomyError.badVector
        }

        let moonParallax = asin(earthRadius / targetDistance)
        let sunSemiDiameter = asin(sunRadiusKilometers / directionDistance)
        let sunParallax = asin(earthRadius / directionDistance)
        let umbraAngle = danjonParallaxFactor * moonParallax - sunSemiDiameter + sunParallax
        let penumbraAngle = danjonParallaxFactor * moonParallax + sunSemiDiameter + sunParallax
        let axialDistance = geometric.axisFraction * directionDistance
        guard axialDistance > 0, axialDistance.isFinite else { throw AstronomyError.badVector }
        let axisAngle = atan2(geometric.axisDistanceKilometers, axialDistance)

        let axisDistance = targetDistance * tan(axisAngle)
        let umbraRadius = targetDistance * tan(umbraAngle)
        let penumbraRadius = targetDistance * tan(penumbraAngle)
        guard axisDistance.isFinite, umbraRadius > 0, penumbraRadius > umbraRadius,
            umbraRadius.isFinite, penumbraRadius.isFinite
        else {
            throw AstronomyError.badTime
        }
        return Shadow(
            time: target.time, axisFraction: geometric.axisFraction, axisDistanceKilometers: axisDistance,
            umbraRadiusKilometers: umbraRadius, penumbraRadiusKilometers: penumbraRadius,
            target: target, direction: direction)
    }

    static func projectedDiscRadius(physicalRadiusKilometers: Double, distanceKilometers: Double) throws -> Double {
        guard physicalRadiusKilometers > 0, distanceKilometers > physicalRadiusKilometers,
            physicalRadiusKilometers.isFinite, distanceKilometers.isFinite
        else {
            throw AstronomyError.badVector
        }
        return distanceKilometers * tan(asin(physicalRadiusKilometers / distanceKilometers))
    }

    /// Area shared by two discs, divided by the area of the first disc.
    static func obscuration(firstRadius: Double, secondRadius: Double, separation: Double) -> Double {
        guard firstRadius > 0, secondRadius > 0, separation >= 0 else { return 0 }
        guard separation < firstRadius + secondRadius else { return 0 }
        if separation == 0 {
            return firstRadius <= secondRadius ? 1 : secondRadius * secondRadius / (firstRadius * firstRadius)
        }

        let intersection =
            (firstRadius * firstRadius - secondRadius * secondRadius + separation * separation) / (2 * separation)
        let radicand = firstRadius * firstRadius - intersection * intersection
        if radicand <= 0 {
            return firstRadius <= secondRadius ? 1 : secondRadius * secondRadius / (firstRadius * firstRadius)
        }

        let height = radicand.squareRoot()
        let firstLens = firstRadius * firstRadius * acos(intersection / firstRadius) - intersection * height
        let secondOffset = separation - intersection
        let secondLens = secondRadius * secondRadius * acos(secondOffset / secondRadius) - secondOffset * height
        return (firstLens + secondLens) / (.pi * firstRadius * firstRadius)
    }

    static let sunRadiusKilometers = 695_700.0
    static let moonMeanRadiusKilometers = 1_737.4
    private static let danjonParallaxFactor = 1.01
}

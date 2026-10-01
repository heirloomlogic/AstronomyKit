//
//  SolarAltitudeObservation.swift
//  AstronomyKit
//
//  Geometric solar altitude with its inputs and derived numerical error bound.
//

import Foundation

/// The Sun's geometric altitude, the inputs that produced it, and the derived
/// numerical error bound from <doc:SolarAltitudeNumerics>.
///
/// Get one from ``Sun/altitudeObservation(at:from:deltaTModel:)``,
/// ``Sun/altitudeObservation(terrestrialTime:from:deltaTModel:)``, or
/// ``Sun/altitudeObservation(universalTime:from:deltaTModel:)``. Each builds
/// the ``AstroTime`` with the matching initializer and an explicit
/// ``DeltaTModel``, so the result records every input the calculation read:
/// both time scales, the model, and the observer. A later
/// ``AstronomyConfig/setDeltaTModel(_:)`` call does not change what a
/// repeated call returns.
///
/// ``altitude`` is bit-identical to
/// `CelestialBody.sun.horizon(at: time, from: observer, refraction: .none).altitude`.
/// ``errorBound`` sums the terms of the article's budget that apply to how
/// the time was built. It covers only what the article derives. The terms the
/// article measures (polynomial evaluation, frame rotation, sidereal time, the
/// horizon transform, the math library, and the Delta T polynomial) have no
/// bound; the article reports their measurements instead, and a certificate
/// has to treat them as evidence about that platform and grid.
///
/// A case the article excludes throws ``Unsupported`` instead of returning a
/// bound.
public struct SolarAltitudeObservation: Sendable, Equatable, Hashable {
    /// The input scale that names the instant the bound is measured from.
    public enum Reference: Sendable, Hashable {
        /// A civil UTC date from 1961 on: TT comes from the bundled offset
        /// table and UT from the model's inverse.
        case civilUTC

        /// A civil date before 1961, taken as UT1: UT is the civil day count
        /// and TT follows the model.
        case civilUT1

        /// A Terrestrial Time; UT comes from the model's inverse.
        case terrestrialTime

        /// A Universal Time; TT follows the model.
        case universalTime
    }

    /// The derived terms that apply to one observation, in degrees.
    public struct ErrorBound: Sendable, Equatable, Hashable {
        /// Calendar rounding and, from 1961 on, the civil UTC to TT
        /// conversion, with what that error carries into the scale the model
        /// derives from it. Zero unless the time came from a `Date`.
        public let civilConversion: Double

        /// The TT to UT inverse when the engine derived UT, or the UT to TT
        /// rounding when it derived TT.
        public let scaleConversion: Double

        /// Light-time termination.
        public let lightTimeTermination: Double

        /// Earth Rotation Angle rounding.
        public let earthRotationAngle: Double

        /// The sum of the four terms. Each addition rounds up when its
        /// floating-point result fell short, so the total is never below the
        /// exact sum.
        public var total: Double {
            let conversions = Self.addingUp(civilConversion, scaleConversion)
            return Self.addingUp(Self.addingUp(conversions, lightTimeTermination), earthRotationAngle)
        }

        /// `a + b`, moved up one unit when the rounded sum is below the exact sum.
        static func addingUp(_ a: Double, _ b: Double) -> Double {
            let sum = a + b
            // Two-sum: the exact error of a rounded sum of finite operands.
            let bVirtual = sum - a
            let error = (a - (sum - bVirtual)) + (b - bVirtual)
            return error > 0 ? sum.nextUp : sum
        }
    }

    /// A case <doc:SolarAltitudeNumerics> excludes from the budget.
    public enum Unsupported: Error, Sendable, Equatable, Hashable {
        /// The input TT, or a TT the light-time loop can reach by backdating,
        /// is outside ``SolarAltitudeObservation/polynomialCoverage``.
        case outsidePolynomialCoverage

        /// The TT lies in a positive Delta T step of the model (1920, 1941,
        /// 1961, or 1986), where the model has no UT and the inverse stores a
        /// pair the model does not relate.
        case terrestrialTimeInDeltaTGap

        /// The civil date is within the calendar rounding of a UTC segment
        /// start, where the stored TT can land on either side of the step.
        case civilDateAtSegmentStart

        /// The observer is farther than
        /// ``SolarAltitudeObservation/maximumObserverHeight`` from the
        /// ellipsoid.
        case observerHeightOutsideBudget
    }

    /// The time the altitude was evaluated at, with both scales and the model.
    public let time: AstroTime

    /// The Delta T model that relates the two scales of ``time`` and that the
    /// light-time loop used.
    public let deltaTModel: DeltaTModel

    /// The observer.
    public let observer: Observer

    /// Which input scale names the instant ``errorBound`` is measured from.
    public let reference: Reference

    /// The geometric altitude in degrees, without refraction.
    public let altitude: Double

    /// The derived numerical error bound.
    public let errorBound: ErrorBound

    /// The TT days from J2000 where the Earth polynomial ephemeris applies:
    /// 1900-01-01 through the end of 2100.
    public static let polynomialCoverage: Range<Double> =
        SolarAltitudeBounds.polynomialStart..<SolarAltitudeBounds.polynomialStop

    /// The width of one Earth polynomial segment in TT days. Boundaries sit at
    /// `polynomialCoverage.lowerBound` plus whole multiples of this width.
    public static let polynomialSegmentDays = SolarAltitudeBounds.polynomialSegmentDays

    /// The most the Sun's direction changes across one polynomial segment
    /// boundary, in degrees. A point observation never pays it; an enclosure
    /// over a time interval widens by this much per boundary the backdated TT
    /// crosses.
    public static let joinDiscontinuityDegrees = SolarAltitudeBounds.joinDegrees

    /// The most the light-time loop backdates the Earth position, in days.
    public static let maximumLightTimeDays = SolarAltitudeBounds.backdateMaxDays

    /// The largest observer height above or below the ellipsoid the budget
    /// covers, in meters.
    public static let maximumObserverHeight = SolarAltitudeBounds.observerHeightMeters

    init(time: AstroTime, reference: Reference, observer: Observer, deltaTModel: DeltaTModel) throws {
        _ = try observer.validatedRaw()
        guard abs(observer.height) <= SolarAltitudeBounds.observerHeightMeters else {
            throw Unsupported.observerHeightOutsideBudget
        }
        let ut = time.universalTime
        let tt = time.terrestrialTime
        guard ut.isFinite, tt.isFinite else { throw AstronomyError.badTime }

        // The TT the model gives for `ut`. A time built from `ut` has exactly it.
        let forwardTT: Double
        let civilConversion: Double
        let scaleConversion: Double
        switch reference {
        case .terrestrialTime, .civilUTC:
            forwardTT = AstroTime(ut: ut, deltaTModel: deltaTModel).terrestrialTime
            // The engine's inverse accepts this residual as converged; a TT in
            // a gap is stored with a UT whose residual exceeds it.
            guard abs(tt - forwardTT) <= Self.inverseTolerance(terrestrialTime: tt) else {
                throw Unsupported.terrestrialTimeInDeltaTGap
            }
            civilConversion = reference == .civilUTC ? SolarAltitudeBounds.civilToTTDegrees : 0
            scaleConversion = SolarAltitudeBounds.ttInverseDegrees
        case .universalTime, .civilUT1:
            forwardTT = tt
            civilConversion = reference == .civilUT1 ? SolarAltitudeBounds.civilToUTDegrees : 0
            scaleConversion = SolarAltitudeBounds.forwardTTDegrees
        }

        // The light-time loop evaluates the Earth at the input TT first, then
        // at the TT derived from `ut - tau` for tau up to the backdate bound.
        let coverage = Self.polynomialCoverage
        let earliest = AstroTime(ut: ut - SolarAltitudeBounds.backdateMaxDays, deltaTModel: deltaTModel)
        let earliestTT = earliest.terrestrialTime
        guard coverage.contains(tt), coverage.contains(forwardTT), coverage.contains(earliestTT) else {
            throw Unsupported.outsidePolynomialCoverage
        }

        self.time = time
        self.deltaTModel = deltaTModel
        self.observer = observer
        self.reference = reference
        self.altitude = try CelestialBody.sun.horizon(at: time, from: observer, refraction: .none).altitude
        self.errorBound = ErrorBound(
            civilConversion: civilConversion,
            scaleConversion: scaleConversion,
            lightTimeTermination: SolarAltitudeBounds.lightTimeDegrees,
            earthRotationAngle: SolarAltitudeBounds.eraDegrees
        )
    }

    /// The residual `|tt - time.tt|` the engine's TT to UT inverse accepts as
    /// converged, as it writes the expression.
    static func inverseTolerance(terrestrialTime tt: Double) -> Double {
        max(SolarAltitudeBounds.inverseToleranceFloorDays, SolarAltitudeBounds.inverseTolerancePerDay * abs(tt))
    }
}

// MARK: - Entry points

extension Sun {
    /// The Sun's geometric altitude at a civil UTC date, with its inputs and
    /// derived error bound.
    ///
    /// The time is `AstroTime(date, deltaTModel: deltaTModel)`. From 1961 on
    /// the bound adds the calendar and civil-to-TT rounding, carried into the
    /// derived UT, and the TT to UT inverse; before 1961 it adds the calendar
    /// rounding taken as UT, carried into the derived TT, and the UT to TT
    /// rounding. Either way it adds light-time termination and Earth Rotation
    /// Angle rounding.
    ///
    /// - Parameters:
    ///   - date: The civil UTC instant.
    ///   - observer: The observer, within 10 km of the ellipsoid.
    ///   - deltaTModel: The Delta T model that relates the time's scales.
    /// - Returns: The altitude, its inputs, and the derived bound.
    /// - Throws: ``SolarAltitudeObservation/Unsupported`` for a case the
    ///   budget excludes, ``AstronomyError/badTime`` for a non-finite date or,
    ///   from 1961 on, a TT the inverse does not converge for,
    ///   ``AstronomyError/invalidParameter`` for an invalid observer.
    public static func altitudeObservation(
        at date: Date,
        from observer: Observer,
        deltaTModel: DeltaTModel
    ) throws -> SolarAltitudeObservation {
        let civilDays = AstroTime.civilDays(of: date)
        let nearSegmentStart = CivilTime.segments.contains { segment in
            abs(civilDays - segment.start) <= SolarAltitudeBounds.civilCalendarDays
        }
        guard !nearSegmentStart else {
            throw SolarAltitudeObservation.Unsupported.civilDateAtSegmentStart
        }
        let civil = AstroTime.civil(days: civilDays, deltaTModel: deltaTModel)
        return try SolarAltitudeObservation(
            time: civil.time,
            reference: civil.fromTable ? .civilUTC : .civilUT1,
            observer: observer,
            deltaTModel: deltaTModel
        )
    }

    /// The Sun's geometric altitude at a Terrestrial Time, with its inputs and
    /// derived error bound.
    ///
    /// The time is `AstroTime(tt: terrestrialTime, deltaTModel: deltaTModel)`.
    /// The bound adds the TT to UT inverse, light-time termination, and Earth
    /// Rotation Angle rounding.
    ///
    /// - Parameters:
    ///   - terrestrialTime: TT days since J2000 noon.
    ///   - observer: The observer, within 10 km of the ellipsoid.
    ///   - deltaTModel: The Delta T model that derives UT.
    /// - Returns: The altitude, its inputs, and the derived bound.
    /// - Throws: ``SolarAltitudeObservation/Unsupported`` for a case the
    ///   budget excludes, ``AstronomyError/badTime`` for a non-finite or
    ///   nonconvergent TT, ``AstronomyError/invalidParameter`` for an invalid
    ///   observer.
    public static func altitudeObservation(
        terrestrialTime: Double,
        from observer: Observer,
        deltaTModel: DeltaTModel
    ) throws -> SolarAltitudeObservation {
        try SolarAltitudeObservation(
            time: AstroTime(tt: terrestrialTime, deltaTModel: deltaTModel),
            reference: .terrestrialTime,
            observer: observer,
            deltaTModel: deltaTModel
        )
    }

    /// The Sun's geometric altitude at a Universal Time, with its inputs and
    /// derived error bound.
    ///
    /// The time is `AstroTime(ut: universalTime, deltaTModel: deltaTModel)`.
    /// The bound adds the UT to TT rounding, light-time termination, and Earth
    /// Rotation Angle rounding. A time the engine derived, such as a search
    /// result or an ``AstroTime/addingDays(_:)`` result, is rebuilt exactly
    /// from its ``AstroTime/universalTime`` and ``AstroTime/deltaTModel``.
    ///
    /// - Parameters:
    ///   - universalTime: UT1 days since J2000 noon.
    ///   - observer: The observer, within 10 km of the ellipsoid.
    ///   - deltaTModel: The Delta T model that derives TT.
    /// - Returns: The altitude, its inputs, and the derived bound.
    /// - Throws: ``SolarAltitudeObservation/Unsupported`` for a case the
    ///   budget excludes, ``AstronomyError/badTime`` for a non-finite UT,
    ///   ``AstronomyError/invalidParameter`` for an invalid observer.
    public static func altitudeObservation(
        universalTime: Double,
        from observer: Observer,
        deltaTModel: DeltaTModel
    ) throws -> SolarAltitudeObservation {
        try SolarAltitudeObservation(
            time: AstroTime(ut: universalTime, deltaTModel: deltaTModel),
            reference: .universalTime,
            observer: observer,
            deltaTModel: deltaTModel
        )
    }
}

//
//  EngineTime.swift
//  AstronomyKit
//
//  The native engine's time value.
//

extension Engine {
    /// A moment on both time scales, with the Delta T model that relates them.
    ///
    /// `ut` is modeled UT1 and `tt` is Terrestrial Time, each in days since
    /// 2000-01-01 12:00 on its own scale. Every time derived from this one, by
    /// adding days, as a search step, or as a light-time backdate, derives its
    /// TT with ``deltaTModel``, so a calculation uses one model from its input
    /// time to its result. Engine code never reads the process default model;
    /// the public layer resolves it once, when a caller gives no model.
    ///
    /// A time whose `ut` or `tt` is not finite is invalid and carries no model.
    /// Its scales are kept as given: a huge finite UT can give an infinite TT,
    /// and the public API still reports that UT. A time derived from an
    /// invalid one uses the fallback model its caller passes; see
    /// ``adding(days:fallback:)``.
    ///
    /// There is no `Equatable` conformance. Public `AstroTime` equality,
    /// hashing and `Codable` use UT only; engine code compares the scale it
    /// means.
    struct Time: Sendable {
        /// Modeled UT1 days since 2000-01-01 12:00 UT1.
        let ut: Double

        /// Terrestrial Time days since 2000-01-01 12:00 TT.
        let tt: Double

        /// The model that derives TT for times made from this one; `nil` when
        /// the time is invalid.
        let deltaTModel: DeltaTModel?

        /// A time with both scales stored as given.
        ///
        /// The model is kept only when both scales are finite.
        init(ut: Double, tt: Double, deltaTModel: DeltaTModel) {
            self.ut = ut
            self.tt = tt
            self.deltaTModel = ut.isFinite && tt.isFinite ? deltaTModel : nil
        }

        /// The time with NaN scales and no model. NaN scales drop the model.
        static let invalid = Time(ut: .nan, tt: .nan, deltaTModel: .espenakMeeus)

        /// Rebuilds a time from recorded scales, as `AstroTime(tt:ut:deltaTModel:)`
        /// does, without deriving either scale or checking the pair against
        /// the model.
        ///
        /// A scale that is not finite gives ``invalid``.
        static func fromPair(ut: Double, tt: Double, deltaTModel: DeltaTModel) -> Time {
            guard ut.isFinite, tt.isFinite else { return .invalid }
            return Time(ut: ut, tt: tt, deltaTModel: deltaTModel)
        }

        /// Whether both scales are finite.
        var isValid: Bool { deltaTModel != nil }
    }
}

// MARK: - Construction from one scale

extension Engine.Time {
    /// The time at modeled UT1 `ut`, with TT from `deltaTModel`:
    /// `tt = ut + ΔT(ut) / 86400`.
    ///
    /// Invalid, with the scales kept, when `ut` or the derived TT is not
    /// finite. Espenak-Meeus TT overflows from about |ut| = 1e158 days.
    init(ut: Double, deltaTModel: DeltaTModel) {
        self.init(
            ut: ut,
            tt: ut + Engine.DeltaT.seconds(ut: ut, model: deltaTModel) / 86_400,
            deltaTModel: deltaTModel
        )
    }

    /// The time at Terrestrial Time `tt`, with UT found by inverting
    /// `deltaTModel`. The result's TT is exactly `tt`.
    ///
    /// Fixed-point iteration starts from `ut = tt` and accepts a UT whose
    /// model TT is within `max(1e-12, 2ε|tt|)` days, where ε = 2.22e-16, so a
    /// large TT converges at the precision a double can hold. Where a positive
    /// Delta T jump leaves TT values that no UT reaches, the iteration
    /// brackets the jump and bisection returns the first representable UT
    /// after it. Where a negative jump gives two solutions, the result is
    /// the one iteration reaches first: the later solution when Delta T is
    /// positive, the earlier when it is negative.
    ///
    /// ``invalid`` for a TT that is not finite, a UT or TT that becomes
    /// non-finite on the way, or no convergence in 128 iterations and 128
    /// bisection steps.
    init(tt: Double, deltaTModel: DeltaTModel) {
        guard tt.isFinite else {
            self = .invalid
            return
        }
        let tolerance = Self.inverseTolerance(tt: tt)
        // A UT whose model TT is within tolerance, stored with TT exactly `tt`.
        func converged(_ time: Engine.Time) -> Engine.Time {
            Engine.Time(ut: time.ut, tt: tt, deltaTModel: deltaTModel)
        }

        var time = Engine.Time(ut: tt, deltaTModel: deltaTModel)
        var below = Engine.Time.invalid
        var above = Engine.Time.invalid
        for _ in 0..<128 {
            let error = tt - time.tt
            guard error.isFinite, time.ut.isFinite else {
                self = .invalid
                return
            }
            if abs(error) <= tolerance {
                self = converged(time)
                return
            }
            if error > 0 {
                below = time
            } else {
                above = time
            }
            time = Engine.Time(ut: time.ut + error, deltaTModel: deltaTModel)
        }

        // A positive Delta T jump leaves a TT gap that no UT reaches, and the
        // iteration has bracketed the jump. Bisect to the first representable
        // UT after it.
        if below.ut.isFinite, above.ut.isFinite, below.ut < above.ut {
            for _ in 0..<128 {
                let ut = below.ut + (above.ut - below.ut) / 2
                if ut == below.ut || ut == above.ut {
                    self = converged(above)
                    return
                }
                time = Engine.Time(ut: ut, deltaTModel: deltaTModel)
                let error = tt - time.tt
                guard error.isFinite else {
                    self = .invalid
                    return
                }
                if abs(error) <= tolerance {
                    self = converged(time)
                    return
                }
                if error > 0 {
                    below = time
                } else {
                    above = time
                }
            }
        }
        self = .invalid
    }

    /// How close, in days, the model TT of a UT must come to `tt` for
    /// ``init(tt:deltaTModel:)`` to accept it: 1e-12 days, or twice the
    /// double epsilon times |`tt`| where that is larger.
    static func inverseTolerance(tt: Double) -> Double {
        max(1.0e-12, 2.0 * Double.ulpOfOne * abs(tt))
    }

    /// The time `days` UT days after this one, with TT derived by this
    /// time's model. `fallback` derives it instead when this time is invalid
    /// and has no model.
    ///
    /// The public layer passes, as `fallback`, the process default it read
    /// for the call, which is what the C engine's `Astronomy_AddDays` does
    /// with a time that carries no Delta T function. A huge UT whose TT
    /// overflowed can therefore come back to a valid time.
    func adding(days: Double, fallback: DeltaTModel) -> Engine.Time {
        Engine.Time(ut: ut + days, deltaTModel: deltaTModel ?? fallback)
    }
}

// MARK: - Civil UTC

extension Engine.Time {
    /// The time of a civil UTC day count since 2000-01-01 12:00 UTC.
    ///
    /// From 1961 the bundled USNO table (``CivilTime``) gives TT and the TT
    /// inverse gives UT. Before 1961, and for a count that is not finite,
    /// the count is taken as UT1, the historical civil proxy. `fromTable`
    /// reports which applied. After the last table entry the last announced
    /// offset holds.
    static func civil(utcDays: Double, deltaTModel: DeltaTModel) -> (time: Engine.Time, fromTable: Bool) {
        if let tt = CivilTime.terrestrialTime(utcDays: utcDays) {
            return (Engine.Time(tt: tt, deltaTModel: deltaTModel), true)
        }
        return (Engine.Time(ut: utcDays, deltaTModel: deltaTModel), false)
    }

    /// Civil UTC days since 2000-01-01 12:00 UTC, the inverse of
    /// ``civil(utcDays:deltaTModel:)``.
    ///
    /// A TT inside a positive leap second maps to the following midnight. Where
    /// a negative historical UTC step repeats civil times, the later
    /// occurrence wins. Before the table, the civil count is UT, capped at the
    /// table's first day. NaN when TT is not finite.
    var utcDays: Double {
        CivilTime.utcDays(terrestrialTime: tt, universalTime: ut)
    }
}

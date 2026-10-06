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
    /// and the public API still reports that UT.
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

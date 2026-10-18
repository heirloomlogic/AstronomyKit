//
//  EngineDeltaTObserved.swift
//  AstronomyKit
//
//  The observed Delta T model: IERS UT1 from 1962, the Morrison-Stephenson-
//  Hohenkerk-Zawilski (2021) spline before it, and HMNAO's long-term
//  length-of-day model outside both.
//

import Foundation

extension Engine.DeltaT {
    /// Delta T from observed Earth rotation, ``DeltaTModel/iersObserved``.
    ///
    /// The tables in `Generated/DeltaTObservedTable.swift` are immutable, so
    /// evaluation needs no initialization call or lock. Regimes, by UT1 days
    /// since J2000:
    ///
    /// - Observed and predicted: the daily rows at 0h UTC, IERS EOP 20 C04
    ///   then IERS Bulletin A rapid values and predictions. Each row's
    ///   abscissa is its UT1, `MJD − 51544.5 + (UT1 − UTC)/86400`, and Delta T
    ///   is linear in UT1 between rows.
    /// - Historical: Table S15 v2020 from −720.0 to the first C04 row, in
    ///   Julian epoch years, rebuilt by the generator as cubic Hermite
    ///   segments through the mean one-sided value and rate at each knot, so
    ///   it is C0 and C1 everywhere. The last segment ends on the first C04
    ///   value and the rate of the first C04 interval.
    /// - Extrapolated: before −720.0 and after the last prediction, the
    ///   integral of lod = 1.72 t − 3.5 sin(2π(t + 0.75)/14) ms, t in Julian
    ///   centuries from 1825.0, with its constant fixed by continuity at the
    ///   join. HMNAO extrapolates the spline this way in both directions.
    ///
    /// Each function performs the operations of the 3.x C engine's
    /// `Astronomy_DeltaT_IersObserved`, `Astronomy_DeltaTUncertainty_IersObserved`
    /// and `Astronomy_DeltaTRegime_IersObserved` in the same order, on the
    /// same generated values.
    enum Observed {
        /// One rebuilt spline segment: Delta T in seconds is
        /// `a0 + t (a1 + t (a2 + t a3))` with `t = (year − start)/(end − start)`.
        struct Segment {
            let start: Double
            let end: Double
            let a0: Double
            let a1: Double
            let a2: Double
            let a3: Double
        }

        /// One HMNAO error estimate.
        struct Knot {
            let year: Double
            let seconds: Double
        }

        /// The daily rows in seconds, with each row's UT1 abscissa.
        struct Rows {
            /// Delta T at each row, in seconds.
            let deltaT: [Double]

            /// The stated error of UT1 − UTC at each row, in seconds.
            let error: [Double]

            /// Each row's UT1 in days since J2000: its 0h UTC day plus
            /// UT1 − UTC.
            let ut: [Double]

            /// Decodes rows of {Delta T, UT1 − UTC, error} in units of 1e-7 s.
            init(packed values: [Double]) {
                let count = values.count / 3
                let firstUT: Double = Observed.firstUT
                var deltaT: [Double] = []
                var ut: [Double] = []
                var error: [Double] = []
                deltaT.reserveCapacity(count)
                ut.reserveCapacity(count)
                error.reserveCapacity(count)
                for row in 0..<count {
                    deltaT.append(values[3 * row] / 1.0e7)
                    // The C engine's abscissa: (first UT + row) + (UT1 − UTC) / 86400.
                    let day: Double = firstUT + Double(row)
                    let ut1MinusUTC: Double = values[3 * row + 1] / 1.0e7
                    ut.append(day + ut1MinusUTC / 86_400.0)
                    error.append(values[3 * row + 2] / 1.0e7)
                }
                self.deltaT = deltaT
                self.ut = ut
                self.error = error
            }
        }

        /// UT1 days since J2000 at the first row's 0h UTC day.
        static let firstUT = Double(firstMJD) - 51_544.5

        /// The Julian epoch year of `ut`: J2000.0 is 2000-01-01 12h, so
        /// J1962.0 is 1962-01-01 0h.
        static func year(ut: Double) -> Double {
            2000.0 + ut / 365.25
        }

        /// The row at or before `ut`, for a `ut` within the rows.
        static func row(at ut: Double) -> Int {
            let abscissae = Self.rows.ut
            let last = abscissae.count - 2
            var row = Swift.min(Swift.max(Int((ut - firstUT).rounded(.down)), 0), last)
            // Abscissae differ from whole UTC days by UT1 − UTC, at most about a second.
            while row > 0 && abscissae[row] > ut { row -= 1 }
            while row < last && abscissae[row + 1] <= ut { row += 1 }
            return row
        }

        /// Delta T in seconds, up to a constant, from integrating the
        /// long-term length-of-day model.
        static func lodIntegral(year: Double) -> Double {
            // Seconds per (ms of lod × century): 36525 days × 1e-3 s.
            let t = (year - lodEpoch) / 100.0
            let phase = 2.0 * Double.pi * (t + lodPhase) / lodPeriod
            let tidal: Double = 0.5 * lodRate * t * t
            let fluctuation: Double = lodAmplitude * lodPeriod / (2.0 * Double.pi) * cos(phase)
            return 36.525 * (tidal + fluctuation)
        }

        /// The rebuilt Table S15 spline at a Julian epoch year from −720.
        static func spline(year: Double) -> Double {
            var low = 0
            var high = spline.count - 1
            while low < high {
                let middle = (low + high + 1) / 2
                if spline[middle].start <= year {
                    low = middle
                } else {
                    high = middle - 1
                }
            }
            let segment = spline[low]
            let t = (year - segment.start) / (segment.end - segment.start)
            return segment.a0 + t * (segment.a1 + t * (segment.a2 + t * segment.a3))
        }

        /// HMNAO's error estimate, linear in the year between its knots, and
        /// growing with the square of the time from 1825.0 beyond them.
        static func epsilon(year: Double) -> Double {
            let last = epsilon.count - 1
            if year <= epsilon[0].year || year >= epsilon[last].year {
                let end = epsilon[year <= epsilon[0].year ? 0 : last]
                let ratio = (year - lodEpoch) / (end.year - lodEpoch)
                return end.seconds * ratio * ratio
            }
            var low = 0
            var high = last
            while high - low > 1 {
                let middle = (low + high) / 2
                if epsilon[middle].year <= year {
                    low = middle
                } else {
                    high = middle
                }
            }
            let f = (year - epsilon[low].year) / (epsilon[high].year - epsilon[low].year)
            return epsilon[low].seconds + f * (epsilon[high].seconds - epsilon[low].seconds)
        }

        /// TT − UT1 in seconds at UT1 `ut` days since J2000. NaN for NaN
        /// input; +infinity for infinite input.
        static func seconds(ut: Double) -> Double {
            if ut.isNaN { return .nan }
            if ut.isInfinite { return .infinity }

            let rows = Self.rows
            if ut < rows.ut[0] {
                let epoch = year(ut: ut)
                if epoch >= spline[0].start { return spline(year: epoch) }
                return spline[0].a0 + (lodIntegral(year: epoch) - lodIntegral(year: spline[0].start))
            }

            let last = rows.ut.count - 1
            let final = rows.ut[last]
            if ut > final {
                return rows.deltaT[last] + (lodIntegral(year: year(ut: ut)) - lodIntegral(year: year(ut: final)))
            }

            let index = row(at: ut)
            let start = rows.ut[index]
            let f = (ut - start) / (rows.ut[index + 1] - start)
            let before = rows.deltaT[index]
            let after = rows.deltaT[index + 1]
            return before + f * (after - before)
        }

        /// The stated uncertainty of ``seconds(ut:)`` in seconds.
        ///
        /// Observed and predicted: the row's stated UT1 − UTC error, linear
        /// between rows, plus `4 f (1 − f)` times the largest measured
        /// interpolation error at fraction `f` of the day. Historical: the
        /// HMNAO error estimate, but never less than the spline's largest
        /// departure from C04 over 1962–2019. Extrapolated: the HMNAO estimate
        /// (quadratic growth about 1825.0 beyond its −2000 and 2500 ends),
        /// never less than the last prediction's. These are stated, sourced
        /// figures of about one standard error, not proved bounds.
        static func uncertainty(ut: Double) -> Double {
            if ut.isNaN { return .nan }
            if ut.isInfinite { return .infinity }

            let rows = Self.rows
            if ut < rows.ut[0] {
                let epoch = year(ut: ut)
                let estimate = epsilon(year: epoch)
                return epoch >= spline[0].start ? Swift.max(estimate, historicalMisfit) : estimate
            }

            let last = rows.ut.count - 1
            if ut > rows.ut[last] {
                return Swift.max(epsilon(year: year(ut: ut)), rows.error[last])
            }

            let index = row(at: ut)
            let start = rows.ut[index]
            let f = (ut - start) / (rows.ut[index + 1] - start)
            let before = rows.error[index]
            let after = rows.error[index + 1]
            return before + f * (after - before) + 4.0 * f * (1.0 - f) * interpolationMax
        }

        /// The source ``seconds(ut:)`` draws on at `ut`; `nil` for NaN input.
        static func regime(ut: Double) -> DeltaTRegime? {
            if ut.isNaN { return nil }
            let rows = Self.rows
            if ut < rows.ut[0] {
                return year(ut: ut) >= spline[0].start ? .historical : .extrapolatedPast
            }
            if ut <= rows.ut[firstPredictedRow - 1] { return .observed }
            if ut <= rows.ut[rows.ut.count - 1] { return .predicted }
            return .extrapolatedFuture
        }
    }
}

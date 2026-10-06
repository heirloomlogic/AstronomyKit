//
//  EngineSearch.swift
//  AstronomyKit
//
//  The ascending-root search and the light-travel iteration, which call a
//  caller's function of time.
//

extension Engine {
    /// The generic root search.
    enum Search {
        /// The most passes ``ascendingRoot(from:to:toleranceSeconds:fallback:_:)``
        /// makes before it throws `noConvergence`.
        static let iterationLimit = 20

        /// The time in the window from `start` to `end` at which `function`
        /// rises through zero: negative before it, zero or positive after.
        ///
        /// The search combines bisection with quadratic interpolation through
        /// the two ends and the midpoint, and assumes the window holds at most
        /// one root. It succeeds only with an ascending bracket: taken in time
        /// order, the earlier end's value is at most zero, the later end's is
        /// at least zero, and one of them is nonzero. Then it returns the
        /// midpoint once half the window is shorter than the tolerance, or an
        /// interpolated root where the fitted slope is positive and the
        /// estimated error is below the tolerance. A single descending root,
        /// or a function that never changes sign in the window, gives `nil`.
        /// `end` may come before `start`.
        ///
        /// `function` first receives `start`, then `end`. Each time the search
        /// derives takes the model of the time it comes from, or `fallback`
        /// when that time is invalid. Midpoints and interpolated roots come
        /// from the window's first bound in argument order, which begins as
        /// `start`; the narrower window tried around an interpolated root
        /// comes from that root. A midpoint adds half the window's TT span to
        /// the first bound's UT.
        ///
        /// - Parameters:
        ///   - start: The first bound of the window.
        ///   - end: The second bound of the window.
        ///   - toleranceSeconds: How close to the root the result must be.
        ///     Its sign is ignored. Zero or NaN never stops the search.
        ///   - fallback: The model for times derived from an invalid time.
        ///   - function: Called synchronously, on this thread, one call at a
        ///     time.
        /// - Returns: The root, or `nil` when the window has no ascending root
        ///   the search can bracket.
        /// - Throws: Whatever `function` throws, unchanged, after which it is
        ///   not called again; `AstronomyError.noConvergence` after
        ///   ``iterationLimit`` passes.
        static func ascendingRoot(
            from start: Engine.Time, to end: Engine.Time, toleranceSeconds: Double, fallback: DeltaTModel,
            _ function: (Engine.Time) throws -> Double
        ) throws -> Engine.Time? {
            var t1 = start
            var t2 = end
            let toleranceDays = abs(toleranceSeconds / Engine.secondsPerDay)
            var f1 = try function(t1)
            var f2 = try function(t2)
            var fmid = 0.0
            var needsMidValue = true
            var iteration = 0

            while true {
                // The callback values decide direction; an interpolated slope
                // alone does not establish an ascending root. A zero end counts
                // only when the other end is nonzero.
                let forward = t1.ut <= t2.ut
                let earlier = forward ? f1 : f2
                let later = forward ? f2 : f1
                let ascendingBracket = earlier <= 0 && later >= 0 && (earlier < 0 || later > 0)

                iteration += 1
                if iteration > iterationLimit {
                    throw AstronomyError.noConvergence
                }

                let dt = (t2.tt - t1.tt) / 2
                let tmid = t1.adding(days: dt, fallback: fallback)
                if ascendingBracket && abs(dt) < toleranceDays {
                    return tmid
                }

                if needsMidValue {
                    fmid = try function(tmid)
                } else {
                    needsMidValue = true
                }

                if let fit = quadraticRoot(tm: tmid.ut, dt: t2.ut - tmid.ut, fa: f1, fm: fmid, fb: f2) {
                    let tq = Engine.Time(ut: fit.ut, deltaTModel: t1.deltaTModel ?? fallback)
                    let fq = try function(tq)
                    if ascendingBracket && fit.slope > 0 {
                        var guess = abs(fq / fit.slope)
                        if guess < toleranceDays {
                            return tq
                        }

                        // Try a narrower window centered on the interpolated root.
                        guess *= 1.2
                        if guess < dt / 10 {
                            let tleft = tq.adding(days: -guess, fallback: fallback)
                            let tright = tq.adding(days: guess, fallback: fallback)
                            if (tleft.ut - t1.ut) * (tleft.ut - t2.ut) < 0,
                                (tright.ut - t1.ut) * (tright.ut - t2.ut) < 0
                            {
                                let fleft = try function(tleft)
                                let fright = try function(tright)
                                if fleft < 0 && fright >= 0 {
                                    f1 = fleft
                                    f2 = fright
                                    t1 = tleft
                                    t2 = tright
                                    fmid = fq
                                    needsMidValue = false
                                    continue
                                }
                            }
                        }
                    }
                }

                // Keep whichever half shows an ascending sign change.
                if (forward && f1 < 0 && fmid >= 0) || (!forward && fmid < 0 && f1 >= 0) {
                    t2 = tmid
                    f2 = fmid
                    continue
                }
                if (forward && fmid < 0 && f2 >= 0) || (!forward && f2 < 0 && fmid >= 0) {
                    t1 = tmid
                    f1 = fmid
                    continue
                }

                // No ascending sign change, or more than one root.
                return nil
            }
        }

        /// The root in -1...1 of the parabola through (-1, `fa`), (0, `fm`)
        /// and (1, `fb`), mapped to UT `tm + x · dt`, with the parabola's slope
        /// there per UT day. `nil` when the curve is flat, has no root in
        /// range, or has two.
        static func quadraticRoot(
            tm: Double, dt: Double, fa: Double, fm: Double, fb: Double
        ) -> (ut: Double, slope: Double)? {
            let q = (fb + fa) / 2 - fm
            let r = (fb - fa) / 2
            let s = fm
            let x: Double
            if q == 0 {
                // A line.
                if r == 0 { return nil }
                x = -s / r
                if x < -1 || x > 1 { return nil }
            } else {
                let u = r * r - 4 * q * s
                if u <= 0 { return nil }
                let ru = u.squareRoot()
                let x1 = (-r + ru) / (2 * q)
                let x2 = (-r - ru) / (2 * q)
                if -1 <= x1 && x1 <= 1 {
                    if -1 <= x2 && x2 <= 1 { return nil }
                    x = x1
                } else if -1 <= x2 && x2 <= 1 {
                    x = x2
                } else {
                    return nil
                }
            }
            return (tm + x * dt, (2 * q * x + r) / dt)
        }
    }

    /// Correction for the time light takes to reach an observer.
    enum LightTravel {
        /// The most positions ``correct(at:fallback:_:)`` requests before it
        /// throws `noConvergence`.
        static let iterationLimit = 10

        /// The position `position` gives at the time light left the target,
        /// for light that reaches the observer at `time`.
        ///
        /// `position` returns the target relative to the observer at a time.
        /// The first call receives `time`. After each call the light time is
        /// the vector's length over ``Engine/speedOfLightAUPerDay``, and the
        /// next time is `time` backdated by it in UT, with TT from `time`'s
        /// model, or `fallback` when `time` is invalid. The iteration stops
        /// when the next time's TT is less than 1e-9 days from the last.
        ///
        /// - Parameters:
        ///   - time: The time light reaches the observer.
        ///   - fallback: The model for backdated times when `time` is invalid.
        ///   - position: Called synchronously, on this thread, one call at a
        ///     time.
        /// - Returns: The last vector `position` returned, with its time set
        ///   to the time that call received.
        /// - Throws: Whatever `position` throws, unchanged, after which it is
        ///   not called again; `AstronomyError.invalidParameter` for a
        ///   distance greater than one light-day; `AstronomyError.noConvergence`
        ///   after ``iterationLimit`` calls.
        static func correct<F: Frame>(
            at time: Engine.Time, fallback: DeltaTModel, _ position: (Engine.Time) throws -> Engine.Vector<F>
        ) throws -> Engine.Vector<F> {
            var backdated = time
            for _ in 0..<iterationLimit {
                var vector = try position(backdated)
                vector.time = backdated
                let distance = vector.length
                // Beyond one light-day the iteration converges poorly.
                if distance > Engine.speedOfLightAUPerDay {
                    throw AstronomyError.invalidParameter
                }
                let next = time.adding(days: -distance / Engine.speedOfLightAUPerDay, fallback: fallback)
                if abs(next.tt - backdated.tt) < 1.0e-9 {
                    return vector
                }
                backdated = next
            }
            throw AstronomyError.noConvergence
        }
    }
}

//
//  EngineSearch.swift
//  AstronomyKit
//
//  Pure-Swift quadratic-interpolation and bisection ascending root finder
//  matching Astronomy_Search and QuadInterp in astronomy.c.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineSearch {
    /// Finds an ascending root (transition from negative to non-negative) in [t1, t2].
    static func find(
        t1 start: AstroTime,
        t2 end: AstroTime,
        dtToleranceSeconds: Double,
        _ function: (AstroTime) throws -> Double
    ) throws -> AstroTime {
        guard start.deltaTModel == end.deltaTModel else {
            throw AstronomyError.invalidParameter
        }
        var t1 = start
        var t2 = end
        let dtDays = abs(dtToleranceSeconds / EngineConstants.secondsPerDay)
        var f1 = try function(t1)
        var f2 = try function(t2)
        var fmid = 0.0
        var calcFmid = true
        let iterLimit = 20
        var iter = 0

        while true {
            iter &+= 1
            if iter > iterLimit {
                throw AstronomyError.noConvergence
            }

            let dt = (t2.terrestrialTime - t1.terrestrialTime) / 2.0
            let tmid = t1.addingDays(dt)
            if abs(dt) < dtDays {
                return tmid
            }

            if calcFmid {
                fmid = try function(tmid)
            } else {
                calcFmid = true
            }

            if let quad = quadInterp(
                tm: tmid.universalTime,
                dt: t2.universalTime - tmid.universalTime,
                fa: f1,
                fm: fmid,
                fb: f2
            ) {
                let tq = AstroTime(ut: quad.t, deltaT: t1.deltaTModel)
                let fq = try function(tq)
                if quad.dfdt != 0.0 {
                    var dtGuess = abs(fq / quad.dfdt)
                    if dtGuess < dtDays {
                        return tq
                    }

                    dtGuess *= 1.2
                    if dtGuess < dt / 10.0 {
                        let tleft = tq.addingDays(-dtGuess)
                        let tright = tq.addingDays(dtGuess)
                        if (tleft.universalTime - t1.universalTime) * (tleft.universalTime - t2.universalTime) < 0.0 {
                            if (tright.universalTime - t1.universalTime) * (tright.universalTime - t2.universalTime)
                                < 0.0
                            {
                                let fleft = try function(tleft)
                                let fright = try function(tright)
                                if fleft < 0.0 && fright >= 0.0 {
                                    f1 = fleft
                                    f2 = fright
                                    t1 = tleft
                                    t2 = tright
                                    fmid = fq
                                    calcFmid = false
                                    continue
                                }
                            }
                        }
                    }
                }
            }

            if f1 < 0.0 && fmid >= 0.0 {
                t2 = tmid
                f2 = fmid
                continue
            }

            if fmid < 0.0 && f2 >= 0.0 {
                t1 = tmid
                f1 = fmid
                continue
            }

            throw AstronomyError.searchFailure
        }
    }

    private static func quadInterp(
        tm: Double,
        dt: Double,
        fa: Double,
        fm: Double,
        fb: Double
    ) -> (t: Double, dfdt: Double)? {
        let q = (fb + fa) / 2.0 - fm
        let r = (fb - fa) / 2.0
        let s = fm
        let x: Double

        if q == 0.0 {
            if r == 0.0 {
                return nil
            }
            x = -s / r
            if x < -1.0 || x > 1.0 {
                return nil
            }
        } else {
            let u = r * r - 4.0 * q * s
            if u <= 0.0 {
                return nil
            }
            let ru = sqrt(u)
            let x1 = (-r + ru) / (2.0 * q)
            let x2 = (-r - ru) / (2.0 * q)
            if -1.0 <= x1 && x1 <= 1.0 {
                if -1.0 <= x2 && x2 <= 1.0 {
                    return nil
                }
                x = x1
            } else if -1.0 <= x2 && x2 <= 1.0 {
                x = x2
            } else {
                return nil
            }
        }

        return (tm + x * dt, (2.0 * q * x + r) / dt)
    }
}

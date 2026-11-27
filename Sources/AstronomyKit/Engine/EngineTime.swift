//
//  EngineTime.swift
//  AstronomyKit
//
//  Pure-Swift time conversions, Delta T models (Observed IERS table,
//  Espenak-Meeus, JPL Horizons), and TT/UT inversion.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineTime {
    static let daysPerTropicalYear = 365.24217
    static let secondsPerDay = 86_400.0

    // Observed Delta T: TT - UT1 in seconds at Julian epochs 1962.0, 1963.0, ...,
    // at ut = 365.25 * (year - 2000) days. From IERS EOP 20 C04 UT1-UTC through
    // 2026-09-27 and IERS Bulletin A predictions after it, retrieved 2026-10-27.
    private static let observedFirstYear = 1962
    private static let observedFadeYears = 10.0
    private static let observedJoinOffset = 0.026074996595710331
    private static let observedLongTermYear = 2150.0
    private static let observedCount = 66

    private struct ObservedTable: @unchecked Sendable {
        let values: UnsafePointer<Double>

        static let shared: ObservedTable = {
            let raw: [Double] = [
                33.997, 34.474, 35.032, 35.742, 36.544, 37.433, 38.296, 39.204,  // 1962
                40.181, 41.170, 42.231, 43.373, 44.485, 45.477, 46.459, 47.519,  // 1970
                48.535, 49.586, 50.540, 51.380, 52.167, 52.957, 53.787, 54.343,  // 1978
                54.870, 55.322, 55.820, 56.300, 56.855, 57.566, 58.310, 59.121,  // 1986
                59.984, 60.786, 61.630, 62.295, 62.966, 63.468, 63.829, 64.091,  // 1994
                64.300, 64.474, 64.574, 64.688, 64.845, 65.147, 65.458, 65.777,  // 2002
                66.070, 66.325, 66.604, 66.907, 67.281, 67.644, 68.103, 68.592,  // 2010
                68.968, 69.220, 69.361, 69.360, 69.295, 69.204, 69.175, 69.138,  // 2018
                69.110, 69.308,  // 2026
            ]
            precondition(raw.count == observedCount)
            let buf = UnsafeMutablePointer<Double>.allocate(capacity: raw.count)
            buf.initialize(from: raw, count: raw.count)
            return ObservedTable(values: UnsafePointer(buf))
        }()
    }

    // MARK: - Delta T Models

    static func deltaTEspenakMeeus(ut: Double) -> Double {
        let y = 2000.0 + ((ut - 14.0) / daysPerTropicalYear)

        if y < -500.0 {
            let u = (y - 1820.0) / 100.0
            return -20.0 + (32.0 * u * u)
        }
        if y < 500.0 {
            let u = y / 100.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            let u5 = u2 * u3
            let u6 = u3 * u3
            return 10583.6 - 1014.41 * u + 33.78311 * u2 - 5.952053 * u3
                - 0.1798452 * u4 + 0.022174192 * u5 + 0.0090316521 * u6
        }
        if y < 1600.0 {
            let u = (y - 1000.0) / 100.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            let u5 = u2 * u3
            let u6 = u3 * u3
            return 1574.2 - 556.01 * u + 71.23472 * u2 + 0.319781 * u3
                - 0.8503463 * u4 - 0.005050998 * u5 + 0.0083572073 * u6
        }
        if y < 1700.0 {
            let u = y - 1600.0
            let u2 = u * u
            let u3 = u * u2
            return 120.0 - 0.9808 * u - 0.01532 * u2 + u3 / 7129.0
        }
        if y < 1800.0 {
            let u = y - 1700.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            return 8.83 + 0.1603 * u - 0.0059285 * u2 + 0.00013336 * u3 - u4 / 1_174_000.0
        }
        if y < 1860.0 {
            let u = y - 1800.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            let u5 = u2 * u3
            let u6 = u3 * u3
            let u7 = u3 * u4
            return 13.72 - 0.332447 * u + 0.0068612 * u2 + 0.0041116 * u3
                - 0.00037436 * u4 + 0.0000121272 * u5 - 0.0000001699 * u6
                + 0.000000000875 * u7
        }
        if y < 1900.0 {
            let u = y - 1860.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            let u5 = u2 * u3
            return 7.62 + 0.5737 * u - 0.251754 * u2 + 0.01680668 * u3
                - 0.0004473624 * u4 + u5 / 233_174.0
        }
        if y < 1920.0 {
            let u = y - 1900.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            return -2.79 + 1.494119 * u - 0.0598939 * u2 + 0.0061966 * u3 - 0.000197 * u4
        }
        if y < 1941.0 {
            let u = y - 1920.0
            let u2 = u * u
            let u3 = u * u2
            return 21.20 + 0.84493 * u - 0.076100 * u2 + 0.0020936 * u3
        }
        if y < 1961.0 {
            let u = y - 1950.0
            let u2 = u * u
            let u3 = u * u2
            return 29.07 + 0.407 * u - u2 / 233.0 + u3 / 2547.0
        }
        if y < 1986.0 {
            let u = y - 1975.0
            let u2 = u * u
            let u3 = u * u2
            return 45.45 + 1.067 * u - u2 / 260.0 - u3 / 718.0
        }
        if y < 2005.0 {
            let u = y - 2000.0
            let u2 = u * u
            let u3 = u * u2
            let u4 = u2 * u2
            let u5 = u2 * u3
            return 63.86 + 0.3345 * u - 0.060374 * u2 + 0.0017275 * u3
                + 0.000651814 * u4 + 0.00002373599 * u5
        }
        if y < 2050.0 {
            let u = y - 2000.0
            return 62.92 + 0.32217 * u + 0.005589 * u * u
        }
        if y < 2150.0 {
            let u = (y - 1820.0) / 100.0
            return -20.0 + 32.0 * u * u - 0.5628 * (2150.0 - y)
        }

        let u = (y - 1820.0) / 100.0
        return -20.0 + (32.0 * u * u)
    }

    static func deltaTJplHorizons(ut: Double) -> Double {
        let limit = 17.0 * daysPerTropicalYear
        let clamped = ut > limit ? limit : ut
        return deltaTEspenakMeeus(ut: clamped)
    }

    @inline(__always)
    private static func deltaTLongTerm(year: Double) -> Double {
        let u = (year - 1820.0) / 100.0
        return -20.0 + 32.0 * u * u
    }

    static func deltaTObserved(ut: Double) -> Double {
        let last = observedCount - 1
        let x = ut / 365.25 + Double(2000 - observedFirstYear)

        if x.isNaN {
            return x
        }

        if x < 0.0 {
            if x <= -observedFadeYears {
                return deltaTEspenakMeeus(ut: ut)
            }
            return deltaTEspenakMeeus(ut: ut) + (1.0 + x / observedFadeYears) * observedJoinOffset
        }

        if x < Double(last) {
            let i = Int(x)
            let table = ObservedTable.shared.values
            let v0 = table[i]
            return v0 + (x - Double(i)) * (table[i &+ 1] - v0)
        }

        let year = x + Double(observedFirstYear)
        let parabola = deltaTLongTerm(year: year)
        if year >= observedLongTermYear {
            return parabola
        }

        let table = ObservedTable.shared.values
        let vLast = table[last]
        let rate = vLast - table[last &- 1]
        let linear = vLast + (x - Double(last)) * rate
        let s = (x - Double(last)) / (observedLongTermYear - Double(observedFirstYear) - Double(last))
        return linear + s * s * (3.0 - 2.0 * s) * (parabola - linear)
    }

    // MARK: - Model Dispatch

    static func deltaT(ut: Double, model: DeltaTModel) -> Double {
        switch model {
        case .observed:
            return deltaTObserved(ut: ut)
        case .espenakMeeus:
            return deltaTEspenakMeeus(ut: ut)
        case .jplHorizons:
            return deltaTJplHorizons(ut: ut)
        }
    }

    static func terrestrialTime(ut: Double, model: DeltaTModel) -> Double {
        ut + deltaT(ut: ut, model: model) / secondsPerDay
    }

    // MARK: - AstroTime Constructors & Arithmetic

    static func timeFromDays(_ ut: Double, deltaT model: DeltaTModel) -> AstroTime {
        AstroTime(ut: ut, tt: terrestrialTime(ut: ut, model: model), deltaTModel: model)
    }

    static func timeFromTT(_ tt: Double, deltaT model: DeltaTModel) -> AstroTime {
        // Extreme-input guard: a non-finite TT never converges, and an oscillating
        // iterate never gets within 1e-12 days.
        guard tt.isFinite else {
            return AstroTime(ut: .nan, tt: .nan, deltaTModel: model)
        }

        var ut = tt
        var curTT = terrestrialTime(ut: ut, model: model)
        var oneBackUT = Double.nan
        var twoBackUT = Double.nan
        var iteration = 0
        while iteration < 128 {
            let err = tt - curTT
            if abs(err) < 1.0e-12 {
                break
            }
            // Exact TT inverse: inside a forward Delta T step the iterates alternate
            // between the two UTs on either side of the step.
            if ut == twoBackUT {
                break
            }
            twoBackUT = oneBackUT
            oneBackUT = ut
            ut += err
            curTT = terrestrialTime(ut: ut, model: model)
            iteration &+= 1
        }
        return AstroTime(ut: ut, tt: tt, deltaTModel: model)
    }

    static func currentTime(deltaT model: DeltaTModel) -> AstroTime {
        var tv = timeval()
        gettimeofday(&tv, nil)
        let sec = Double(tv.tv_sec) + Double(tv.tv_usec) / 1.0e6
        let ut = (sec / secondsPerDay) - 10_957.5
        return AstroTime(ut: ut, tt: terrestrialTime(ut: ut, model: model), deltaTModel: model)
    }

    @inline(__always)
    private static func clampInt32(_ value: Int) -> Int64 {
        if value < Int(Int32.min) {
            return Int64(Int32.min)
        }
        if value > Int(Int32.max) {
            return Int64(Int32.max)
        }
        return Int64(value)
    }

    static func makeTime(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Double,
        deltaT model: DeltaTModel
    ) -> AstroTime {
        // Clamp components to Int32 before Int64 calendar arithmetic (matches AstroTime contract).
        let y = clampInt32(year)
        let m = clampInt32(month)
        let d = clampInt32(day)
        let h = clampInt32(hour)
        let min = clampInt32(minute)
        let f = (14 - m) / 12

        // Fliegel & Van Flendern (1968), shifted to support years back to -999,999.
        let y2000 =
            (d - 365_972_956)
            + (1461 * (y + 1_000_000 - f)) / 4
            + (367 * (m - 2 + 12 * f)) / 12
            - (3 * ((y + 1_000_100 - f) / 100)) / 4

        let ut =
            (Double(y2000) - 0.5)
            + (Double(h) / 24.0)
            + (Double(min) / 1440.0)
            + (second / secondsPerDay)
        return AstroTime(ut: ut, tt: terrestrialTime(ut: ut, model: model), deltaTModel: model)
    }

    static func addDays(_ time: AstroTime, _ days: Double) -> AstroTime {
        let ut = time.ut + days
        return AstroTime(
            ut: ut,
            tt: terrestrialTime(ut: ut, model: time.deltaTModel),
            deltaTModel: time.deltaTModel
        )
    }

    @inline(__always)
    static func addTerrestrialDays(_ time: AstroTime, _ days: Double) -> AstroTime {
        AstroTime(ut: time.ut + days, tt: time.tt + days, deltaTModel: time.deltaTModel)
    }
}

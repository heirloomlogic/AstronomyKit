import CLibAstronomy
import Foundation
import Testing

@testable import AstronomyModelPrototype

@Suite("Native Sun pilot")
struct SunPilotTests {
    @Test("Explicit time captures both supported models and backdating")
    func timeCapture() {
        for model in PilotDeltaT.allCases {
            for ut in [-1_000_000.0, -36_524.5, -0.0, 0.0, 6_210.0, 36_889.5, 1_000_000.0] {
                let native = PilotTime(ut: ut, model: model)
                let function: astro_deltat_func =
                    model == .espenakMeeus ? Astronomy_DeltaT_EspenakMeeus : Astronomy_DeltaT_JplHorizons
                let oracle = Astronomy_TimeFromDaysWithDeltaT(ut, function)
                #expect(native.ut.bitPattern == oracle.ut.bitPattern)
                #expect(native.tt.bitPattern == oracle.tt.bitPattern)
                #expect(native.adding(days: -0.005).model == model)
                #expect(native.adding(days: -0.005).tt == Astronomy_AddDays(oracle, -0.005).tt)
            }
        }
    }

    @Test("Earth polynomial and full model agree with the C evaluator")
    func earth() throws {
        for tt in [
            -1_000_000.0, -36_524.5.nextDown, -36_524.5, -36_516.5.nextDown, -36_516.5, 0.0,
            36_889.5.nextDown, 36_889.5, 1_000_000.0,
        ] {
            let actual = try SunPilot.earth(tt: tt)
            let time = Astronomy_TimeFromPair(0, tt, Astronomy_DeltaT_EspenakMeeus)
            let expected = Astronomy_HelioVector(BODY_EARTH, time)
            #expect(abs(actual.vector.x - expected.x) <= 1e-12)
            #expect(abs(actual.vector.y - expected.y) <= 1e-12)
            #expect(abs(actual.vector.z - expected.z) <= 1e-12)
        }
        #expect(try SunPilot.earth(tt: -36_525).usedFallback)
        #expect(try !SunPilot.earth(tt: 0).usedFallback)
    }

    @Test("Native geometric altitude matches C with extreme observers")
    func altitude() throws {
        for model in PilotDeltaT.allCases {
            for ut in [-500_000.0, -36_525.0, 0.0, 9_770.123, 36_900.0, 500_000.0] {
                for latitude in [-90.0, -45.0, 0.0, 89.999, 90.0] {
                    let observer = PilotObserver(latitude: latitude, longitude: 179.999, height: 8_848)
                    let actual = try SunPilot.observe(
                        time: PilotTime(ut: ut, model: model), observer: observer)
                    let function: astro_deltat_func =
                        model == .espenakMeeus ? Astronomy_DeltaT_EspenakMeeus : Astronomy_DeltaT_JplHorizons
                    var time = Astronomy_TimeFromDaysWithDeltaT(ut, function)
                    let site = Astronomy_MakeObserver(latitude, observer.longitude, observer.height)
                    let equ = Astronomy_Equator(BODY_SUN, &time, site, EQUATOR_OF_DATE, ABERRATION)
                    let hor = Astronomy_Horizon(&time, site, equ.ra, equ.dec, REFRACTION_NONE)
                    #expect(abs(actual.altitude - hor.altitude) <= 1e-8)
                    #expect(abs(actual.distance - equ.dist) <= max(1e-12, abs(equ.dist) * 1e-12))
                    #expect(actual.iterations >= 2 && actual.iterations <= 10)
                }
            }
        }
    }

    @Test("Full-series control and replay keep numerical results stable")
    func fullSeriesAndReplay() throws {
        let polynomial = try SunPilot.earth(tt: 0)
        let full = try SunPilot.earth(tt: 0, forceFullSeries: true)
        #expect(full.usedFallback)
        #expect(abs(polynomial.vector.x - full.vector.x) <= 1e-12)
        #expect(abs(polynomial.vector.y - full.vector.y) <= 1e-12)
        #expect(abs(polynomial.vector.z - full.vector.z) <= 1e-12)
        let site = PilotObserver(latitude: 35, longitude: -80, height: 100)
        var evaluator = PilotEvaluator()
        for model in PilotDeltaT.allCases {
            let time = PilotTime(ut: 40_000, model: model)
            let first = try evaluator.observe(time: time, observer: site)
            let second = try evaluator.observe(time: time, observer: site)
            #expect(first.altitude.bitPattern == second.altitude.bitPattern)
            #expect(first.geocentric.x.bitPattern == second.geocentric.x.bitPattern)
            #expect(first.fallbackEvaluations > 0)
            var perturbed = PilotEvaluator(fullSeriesAmplitudeScale: 1.000001)
            let control = try perturbed.observe(time: time, observer: site)
            #expect(abs(first.distance - control.distance) > 1e-12)
        }
    }

    @Test("Independent evaluators can execute concurrently")
    func concurrency() async throws {
        let expected = try SunPilot.observe(
            time: PilotTime(ut: 40_000), observer: PilotObserver(latitude: 90, longitude: 180, height: 0))
        try await withThrowingTaskGroup(of: UInt64.self) { group in
            for _ in 0..<16 {
                group.addTask {
                    var evaluator = PilotEvaluator()
                    return try evaluator.observe(
                        time: PilotTime(ut: 40_000), observer: PilotObserver(latitude: 90, longitude: 180, height: 0)
                    ).altitude.bitPattern
                }
            }
            for try await bits in group { #expect(bits == expected.altitude.bitPattern) }
        }
    }

    @Test("Nonfinite time and observer inputs fail without trapping")
    func invalid() {
        for value in [Double.nan, .infinity, -.infinity, 1_461_001] {
            #expect(throws: PilotError.self) { try SunPilot.earth(tt: value) }
        }
        for value in [Double.nan, .infinity, -.infinity] {
            for observer in [
                PilotObserver(latitude: value, longitude: 0, height: 0),
                PilotObserver(latitude: 0, longitude: value, height: 0),
                PilotObserver(latitude: 0, longitude: 0, height: value),
            ] {
                #expect(throws: PilotError.badTime) {
                    try SunPilot.observe(time: PilotTime(ut: 0), observer: observer)
                }
            }
            let pair = PilotTime(ut: value, tt: 0, model: .espenakMeeus)
            #expect(pair.ut.isNaN && pair.tt.isNaN)
        }
    }
}

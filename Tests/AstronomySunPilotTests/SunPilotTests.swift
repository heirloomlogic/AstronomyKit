import CLibAstronomy
import Foundation
import Testing

@testable import AstronomyModelPrototype
@testable import AstronomySunPilotRunner

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite("Native Sun pilot")
struct SunPilotTests {
    @Test("Fixed nutation terms retain every archived scalar and bounds")
    func fixedNutationTerms() throws {
        #expect(PrototypeModelData.nutationTerm(at: -1) == nil)
        #expect(PrototypeModelData.nutationTerm(at: PrototypeModelData.nutationRowCount) == nil)
        #expect(PrototypeModelData.nutationTerm(at: Int.max) == nil)
        for index in 0..<PrototypeModelData.nutationRowCount {
            let expected = try #require(PrototypeModelData.nutationRow(at: index))
            let actual = try #require(PrototypeModelData.nutationTerm(at: index))
            let multipliers = [actual.m0, actual.m1, actual.m2, actual.m3, actual.m4]
            let coefficients = [actual.c0, actual.c1, actual.c2, actual.c3, actual.c4, actual.c5]
            #expect(multipliers.map(\.bitPattern) == expected.multipliers.map { Double($0).bitPattern })
            #expect(coefficients.map(\.bitPattern) == expected.coefficientBits)
        }
    }

    @Test("Streamed Earth fallback retains decoded expression order and compensation")
    func streamedEarth() throws {
        let series = (0..<3).map { coordinate in
            PrototypeModelData.vsopSeries.filter {
                $0.body == PrototypeBody.earth.rawValue && $0.coordinate == coordinate
            }.map { metadata in
                (metadata.offset..<metadata.offset + metadata.count).map { index in
                    PrototypeModelData.vsopTermBitPatterns(at: index)!
                }
            }
        }
        func decoded(_ tt: Double, scale: Double) -> PilotVector {
            let t = tt / 365250.0
            func coordinate(_ axis: Int) -> Double {
                var power = 1.0
                var total = 0.0
                var totalCompensation = 0.0
                for terms in series[axis] {
                    var sum = 0.0
                    var compensation = 0.0
                    for term in terms {
                        let amplitude = Double(bitPattern: term.amplitude) * scale
                        SunPilot.compensatedAdd(
                            &sum, &compensation,
                            amplitude
                                * cos(Double(bitPattern: term.phase) + t * Double(bitPattern: term.frequency)))
                    }
                    sum += compensation
                    var increment = power * sum
                    if axis == 0 { increment = increment.truncatingRemainder(dividingBy: 2 * .pi) }
                    SunPilot.compensatedAdd(&total, &totalCompensation, increment)
                    power *= t
                }
                return total + totalCompensation
            }
            let lon = coordinate(0)
            let lat = coordinate(1)
            let radius = coordinate(2)
            let rcoslat = radius * cos(lat)
            return PilotVector(x: rcoslat * cos(lon), y: rcoslat * sin(lon), z: radius * sin(lat))
        }
        for tt in [-1_461_000.0, -36_524.5.nextDown, -36_524.5, -0.0, 0.0, 36_889.5, 1_461_000.0] {
            for scale in [1.0, 1.000001] {
                let actual = SunPilot.fullEarth(tt: tt, amplitudeScale: scale)
                let expected = decoded(tt, scale: scale)
                #expect(actual.x.bitPattern == expected.x.bitPattern)
                #expect(actual.y.bitPattern == expected.y.bitPattern)
                #expect(actual.z.bitPattern == expected.z.bitPattern)
            }
        }
    }

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
                        time: PilotTime(ut: 40_000),
                        observer: PilotObserver(latitude: 90, longitude: 180, height: 0)
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

    @Test("Foundation-free JSON preserves decoded scalar bits and omitted fields")
    func serialization() throws {
        struct Scalars: Decodable { let x: Double }
        for value in [
            0.0, -0.0, Double.leastNonzeroMagnitude, .leastNormalMagnitude, .greatestFiniteMagnitude, 1.0,
            -1.0, 1.0.nextUp,
        ] {
            var sample = Sample(status: "success")
            sample.x = value
            let actual = try sample.json()
            let expected = try JSONEncoder().encode(sample)
            let decoded = try JSONDecoder().decode(Scalars.self, from: Data(actual.utf8))
            let reference = try JSONDecoder().decode(Scalars.self, from: expected)
            #expect(decoded.x.bitPattern == reference.x.bitPattern)
            let object = try #require(
                JSONSerialization.jsonObject(with: Data(actual.utf8)) as? [String: Any])
            #expect(Set(object.keys) == ["status", "x"])
        }
        for status in ["bad-time", "invalid-parameter", "no-converge", "bad-vector"] {
            #expect(try Sample(status: status).json() == "{\"status\":\"\(status)\"}")
        }
        var sample = Sample(status: "success")
        sample.fallback = false
        sample.iterations = Int.max
        sample.fallbackEvaluations = 0
        let actual = try JSONSerialization.jsonObject(with: Data(sample.json().utf8)) as? NSDictionary
        let expected =
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample)) as? NSDictionary
        #expect(actual == expected)
        let workload = Runner.Workload(
            operations: Int.max, elapsedNanoseconds: UInt64.max, checksum: -0.0)
        struct DecodedWorkload: Decodable {
            let operations: Int
            let elapsedNanoseconds: UInt64
            let checksum: Double
        }
        let decoded = try JSONDecoder().decode(DecodedWorkload.self, from: Data(workload.json().utf8))
        #expect(decoded.operations == Int.max && decoded.elapsedNanoseconds == UInt64.max)
        #expect(decoded.checksum.bitPattern == (-0.0).bitPattern)
    }

    @Test("JSON escaping and nonfinite errors preserve the output contract")
    func serializationErrors() throws {
        let status = "quote\" slash\\ newline\n tab\t nul\0 café 🌞"
        struct Status: Decodable { let status: String }
        let sample = Sample(status: status)
        let decoded = try JSONDecoder().decode(Status.self, from: Data(sample.json().utf8))
        #expect(decoded.status == status)
        #expect(try sample.json() == sample.json())
        for value in [Double.nan, .infinity, -.infinity] {
            var invalid = Sample(status: "success")
            invalid.x = value
            #expect(throws: PilotOutputError.nonfiniteNumber) { try invalid.json() }
            #expect(throws: EncodingError.self) { try JSONEncoder().encode(invalid) }
            #expect(throws: PilotOutputError.nonfiniteNumber) {
                try Runner.Workload(operations: 1, elapsedNanoseconds: 0, checksum: value).json()
            }
        }
    }

    @Test("Monotonic clock validates conversion and advances without wall time")
    func monotonicClock() throws {
        #expect(try PilotClock.nanoseconds(seconds: 12, nanoseconds: 345) == 12_000_000_345)
        #expect(
            try PilotClock.nanoseconds(seconds: 18_446_744_073, nanoseconds: 709_551_615) == UInt64.max)
        for (seconds, nanoseconds) in [
            (-1, 0), (0, -1), (0, 1_000_000_000), (Int64.max, 0), (18_446_744_073, 709_551_616),
        ] {
            #expect(throws: PilotOutputError.invalidClock) {
                try PilotClock.nanoseconds(seconds: Int64(seconds), nanoseconds: Int64(nanoseconds))
            }
        }
        let first = try PilotClock.now()
        let second = try PilotClock.now()
        #expect(second >= first)
    }

    @Test("Checked delivery retains bytes across short writes and interruptions")
    func outputDelivery() throws {
        let expected = Array("café 🌞\n".utf8)
        var delivered: [UInt8] = []
        var interrupted = false
        try expected.withUnsafeBytes { buffer in
            try PilotOutput.writeAll(buffer) { address, count in
                if !interrupted {
                    interrupted = true
                    errno = EINTR
                    return -1
                }
                let partial = min(count, 2)
                delivered += UnsafeRawBufferPointer(start: address, count: partial)
                return partial
            }
        }
        #expect(delivered == expected)
        try expected.withUnsafeBytes { buffer in
            #expect(throws: PilotOutputError.outputWriteFailed(EIO)) {
                try PilotOutput.writeAll(buffer) { _, _ in
                    errno = EIO
                    return -1
                }
            }
            #expect(throws: PilotOutputError.outputNoProgress) {
                try PilotOutput.writeAll(buffer) { _, _ in 0 }
            }
        }
        let empty: [UInt8] = []
        try empty.withUnsafeBytes { buffer in
            try PilotOutput.writeAll(buffer) { _, _ in
                Issue.record("Empty output must not call the writer")
                return 0
            }
        }
    }
}

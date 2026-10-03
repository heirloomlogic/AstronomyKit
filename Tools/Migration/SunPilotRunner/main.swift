import AstronomyModelPrototype
import Foundation

struct Sample: Encodable {
    let status: String
    var ut, tt, x, y, z, gx, gy, gz, ra, dec, distance, altitude: Double?
    var fallback: Bool?
    var iterations, fallbackEvaluations: Int?
}

@main
struct Runner {
    static func main() throws {
        if let index = CommandLine.arguments.firstIndex(of: "--rss-stage"),
            CommandLine.arguments.indices.contains(index + 1)
        {
            try rssStage(CommandLine.arguments[index + 1])
            return
        }
        if CommandLine.arguments.contains("--performance") {
            try performance()
            return
        }
        let scale = CommandLine.arguments.contains("--perturb-fallback") ? 1.000001 : 1.0
        var evaluator = PilotEvaluator(fullSeriesAmplitudeScale: scale)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        while let line = readLine() {
            let fields = line.split(separator: " ")
            guard fields.count == 7, let model = PilotDeltaT(rawValue: String(fields[0])),
                let value = Double(fields[2]), let latitude = Double(fields[3]),
                let longitude = Double(fields[4]), let height = Double(fields[5]), let pairUT = Double(fields[6])
            else {
                throw PilotError.invalidParameter
            }
            // TT-pair cases isolate polynomial seams from inverse Delta T rounding.
            let time =
                fields[1] == "pair"
                ? PilotTime(ut: pairUT, tt: value, model: model)
                : PilotTime(ut: value, model: model)
            var sample = Sample(status: "success")
            do {
                let earth = try SunPilot.earth(tt: time.tt, fullSeriesAmplitudeScale: scale)
                let observation = try evaluator.observe(
                    time: time,
                    observer: PilotObserver(latitude: latitude, longitude: longitude, height: height))
                sample.ut = time.ut
                sample.tt = time.tt
                sample.x = earth.vector.x
                sample.y = earth.vector.y
                sample.z = earth.vector.z
                sample.fallback = earth.usedFallback
                sample.gx = observation.geocentric.x
                sample.gy = observation.geocentric.y
                sample.gz = observation.geocentric.z
                sample.ra = observation.rightAscension
                sample.dec = observation.declination
                sample.distance = observation.distance
                sample.altitude = observation.altitude
                sample.iterations = observation.iterations
                sample.fallbackEvaluations = observation.fallbackEvaluations
            } catch {
                let status: String
                switch error {
                case PilotError.badTime: status = "bad-time"
                case PilotError.invalidParameter: status = "invalid-parameter"
                case PilotError.noConverge: status = "no-converge"
                case PilotError.badVector: status = "bad-vector"
                default: throw error
                }
                sample = Sample(status: status)
            }
            FileHandle.standardOutput.write(try encoder.encode(sample))
            FileHandle.standardOutput.write(Data([10]))
        }
    }

    struct Workload: Encodable {
        let operations: Int
        let elapsedNanoseconds: UInt64
        let checksum: Double
    }

    static func workload(_ mode: String) throws -> Workload {
        let site = PilotObserver(latitude: 35, longitude: -80, height: 100)
        var evaluator = PilotEvaluator()
        let count = mode == "firstAccess" ? 1 : 200
        let epoch = mode.contains("Fallback") ? 40_000.0 : 9_000.0
        if mode.hasPrefix("repeated") {
            _ = try evaluator.observe(time: PilotTime(ut: epoch), observer: site)
        }
        let start = DispatchTime.now().uptimeNanoseconds
        var checksum = 0.0
        for index in 0..<count {
            let ut = epoch + (mode.hasPrefix("fresh") ? Double(index) * 0.125 : 0)
            let value = try evaluator.observe(time: PilotTime(ut: ut), observer: site)
            checksum += value.altitude + value.distance
        }
        return Workload(
            operations: count, elapsedNanoseconds: DispatchTime.now().uptimeNanoseconds - start,
            checksum: checksum)
    }

    static func write(_ value: Double) {
        FileHandle.standardOutput.write(Data("\(value)\n".utf8))
    }

    static func rssStage(_ stage: String) throws {
        let site = PilotObserver(latitude: 35, longitude: -80, height: 100)
        switch stage {
        case "startup":
            write(0)
        case "serialization":
            FileHandle.standardOutput.write(try JSONEncoder().encode(Workload(operations: 0, elapsedNanoseconds: 0, checksum: 0)))
            FileHandle.standardOutput.write(Data([10]))
        case "polynomialEarth":
            let value = try SunPilot.earth(tt: 9_000)
            write(value.vector.x + value.vector.y + value.vector.z)
        case "fallbackEarth":
            let value = try SunPilot.earth(tt: 40_000)
            write(value.vector.x + value.vector.y + value.vector.z)
        case "polynomialCache", "fallbackCache":
            let epoch = stage == "fallbackCache" ? 40_000.0 : 9_000.0
            var evaluator = PilotEvaluator()
            let first = try evaluator.observe(time: PilotTime(ut: epoch), observer: site)
            let second = try evaluator.observe(time: PilotTime(ut: epoch), observer: site)
            write(first.altitude + first.distance + second.altitude + second.distance)
        case "firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback":
            write(try workload(stage).checksum)
        case "aggregate":
            try performance()
        default:
            throw PilotError.invalidParameter
        }
    }

    static func performance() throws {
        var report: [String: Workload] = [:]
        for mode in [
            "firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback",
        ] {
            report[mode] = try workload(mode)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data([10]))
    }
}

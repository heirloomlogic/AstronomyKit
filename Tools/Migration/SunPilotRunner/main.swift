import AstronomyModelPrototype

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
        while let line = readLine() {
            let fields = line.split(separator: " ")
            guard fields.count == 7, let model = PilotDeltaT(rawValue: String(fields[0])),
                let value = Double(fields[2]), let latitude = Double(fields[3]),
                let longitude = Double(fields[4]), let height = Double(fields[5]),
                let pairUT = Double(fields[6])
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
            print(try sample.json())
        }
    }

    struct Workload: Encodable {
        let operations: Int
        let elapsedNanoseconds: UInt64
        let checksum: Double
    }

    static func workload(_ mode: String, evaluator: inout PilotEvaluator) throws -> Workload {
        let site = PilotObserver(latitude: 35, longitude: -80, height: 100)
        let count = mode == "firstAccess" ? 1 : 200
        let epoch = mode.contains("Fallback") ? 40_000.0 : 9_000.0
        if mode.hasPrefix("repeated") {
            _ = try evaluator.observe(time: PilotTime(ut: epoch), observer: site)
        }
        let start = try PilotClock.now()
        var checksum = 0.0
        for index in 0..<count {
            let ut = epoch + (mode.hasPrefix("fresh") ? Double(index) * 0.125 : 0)
            let value = try evaluator.observe(time: PilotTime(ut: ut), observer: site)
            checksum += value.altitude + value.distance
        }
        return Workload(
            operations: count, elapsedNanoseconds: try PilotClock.now() - start,
            checksum: checksum)
    }

    static func write(_ value: Double) {
        print(value)
    }

    static func rssStage(_ stage: String) throws {
        let site = PilotObserver(latitude: 35, longitude: -80, height: 100)
        switch stage {
        case "startup":
            write(0)
        case "serialization":
            print(try Workload(operations: 0, elapsedNanoseconds: 0, checksum: 0).json())
        case "polynomialEarth":
            let value = try SunPilot.earth(tt: PilotTime(ut: 9_000).tt)
            write(value.vector.x + value.vector.y + value.vector.z)
        case "fallbackEarth":
            let value = try SunPilot.earth(tt: PilotTime(ut: 40_000).tt)
            write(value.vector.x + value.vector.y + value.vector.z)
        case "polynomialCache", "fallbackCache":
            let epoch = stage == "fallbackCache" ? 40_000.0 : 9_000.0
            var evaluator = PilotEvaluator()
            let first = try evaluator.observe(time: PilotTime(ut: epoch), observer: site)
            let second = try evaluator.observe(time: PilotTime(ut: epoch), observer: site)
            write(first.altitude + first.distance + second.altitude + second.distance)
        case "firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback",
            "repeatedFallback":
            var evaluator = PilotEvaluator()
            write(try workload(stage, evaluator: &evaluator).checksum)
        case "aggregate":
            try performance()
        default:
            throw PilotError.invalidParameter
        }
    }

    static func performance() throws {
        var report: [String: Workload] = [:]
        var evaluator = PilotEvaluator()
        for mode in [
            "firstAccess", "freshPolynomial", "repeatedPolynomial", "freshFallback", "repeatedFallback",
        ] {
            report[mode] = try workload(mode, evaluator: &evaluator)
        }
        print(PilotJSON.object(try report.mapValues { try $0.json() }))
    }
}

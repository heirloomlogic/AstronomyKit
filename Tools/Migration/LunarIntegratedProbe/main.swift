import Foundation

// Isolated development integration; no public AstronomyKit model is replaced.
struct CandidateState {
    let position: SIMD3<Double>
    let velocity: SIMD3<Double>
    let correctionSeconds: Double
    let datePlane: [[Double]]
}

func nativeState(_ jd: Double, _ coefficients: LunarCoefficients) throws -> CandidateState {
    guard jd.isFinite, (2_415_020.5...2_499_391.5).contains(jd) else {
        throw ProbeError.invalidRequest
    }
    let offset = jd - 2_451_545
    let correction = eraDtdb(2_451_545, offset, 0, 0, 0, 0)
    var first = 0.0
    var second = 0.0
    guard eraTttdb(2_451_545, offset, correction, &first, &second) == 0 else {
        throw ProbeError.invalidRequest
    }
    let state = try coefficients.state(tdb1: first, tdb2: second)
    var matrix = Array(repeating: (0.0, 0.0, 0.0), count: 3)
    matrix.withUnsafeMutableBufferPointer { eraEcm06(2_451_545, offset, $0.baseAddress) }
    return CandidateState(
        position: state.0, velocity: state.1, correctionSeconds: correction,
        datePlane: matrix.map { [$0.0, $0.1, $0.2] })
}

func scalar(_ jd: Double, _ family: String, _ coefficients: LunarCoefficients) throws -> Double {
    let state = try nativeState(jd, coefficients)
    let value: Double
    switch family {
    case "apsis":
        value =
            state.position.x * state.velocity.x + state.position.y * state.velocity.y + state
            .position.z * state.velocity.z
    case "node":
        value = zip(state.datePlane[2], [state.position.x, state.position.y, state.position.z])
            .reduce(0) { $0 + $1.0 * $1.1 }
    default: throw ProbeError.invalidRequest
    }
    guard value.isFinite else { throw ProbeError.invalidRequest }
    return value
}

func events(_ start: Double, _ stop: Double, _ family: String, _ coefficients: LunarCoefficients)
    throws -> [[String: Any]]
{
    guard start.isFinite, stop.isFinite, stop > start, stop - start <= 366,
        start >= 2_415_020.5, stop <= 2_499_391.5, ["apsis", "node"].contains(family)
    else { throw ProbeError.invalidRequest }
    var output: [[String: Any]] = []
    var leftJD = start
    var left = try scalar(start, family, coefficients)
    let count = Int(ceil((stop - start) * 24))
    for index in 1...count {
        let rightJD = min(stop, start + Double(index) / 24)
        let right = try scalar(rightJD, family, coefficients)
        if left == 0 || right == 0 || (left < 0) != (right < 0) {
            var lower = leftJD
            var upper = rightJD
            var lowerValue = left
            if left == 0 {
                upper = lower
            } else if right == 0 {
                lower = upper
            } else {
                for _ in 0..<32 {
                    let middle = lower + (upper - lower) / 2
                    if (upper - lower) * 86_400 <= 0.0005 || middle == lower || middle == upper {
                        break
                    }
                    let value = try scalar(middle, family, coefficients)
                    if (value < 0) == (lowerValue < 0) {
                        lower = middle
                        lowerValue = value
                    } else {
                        upper = middle
                    }
                }
            }
            let root = lower + (upper - lower) / 2
            let previous = output.last?["julianDateTT"] as? Double
            if root >= start && root < stop
                && (previous == nil || abs(root - previous!) * 86_400 > 0.001)
            {
                let kind =
                    family == "apsis"
                    ? (right > left ? "pericenter" : "apocenter")
                    : (right > left ? "ascending" : "descending")
                output.append([
                    "julianDateTT": root, "kind": kind,
                    "finalBracketWidthSeconds": (upper - lower) * 86_400,
                ])
            }
        }
        leftJD = rightJD
        left = right
    }
    return output
}

func runIntegrated() throws {
    let arguments = CommandLine.arguments
    guard
        (arguments.count == 3 && arguments[1] == "batch")
            || (arguments.count == 4 && arguments[1] == "benchmark")
    else { throw ProbeError.invalidArguments }
    let begin = DispatchTime.now().uptimeNanoseconds
    let coefficients = try LunarCoefficients(path: arguments[2])
    let loadNanoseconds = DispatchTime.now().uptimeNanoseconds - begin
    if arguments[1] == "batch" {
        while let line = readLine() {
            do {
                guard
                    let request = try JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any], let operation = request["operation"] as? String
                else { throw ProbeError.invalidRequest }
                var result: [String: Any] = ["status": "success", "request": request]
                switch operation {
                case "state":
                    let jd = try number(request["julianDateTT"])
                    guard jd >= 2_415_020.5, jd < 2_499_391.5 else {
                        throw ProbeError.invalidRequest
                    }
                    let state = try nativeState(jd, coefficients)
                    result["julianDateTT"] = jd
                    result["tdbMinusTTSeconds"] = state.correctionSeconds
                    result["datePlane"] = state.datePlane
                    result["positionKm"] = [state.position.x, state.position.y, state.position.z]
                    result["velocityKmPerTDBDay"] = [
                        state.velocity.x, state.velocity.y, state.velocity.z,
                    ]
                case "events":
                    guard let family = request["family"] as? String else {
                        throw ProbeError.invalidRequest
                    }
                    result["events"] = try events(
                        number(request["startJulianDateTT"]), number(request["stopJulianDateTT"]),
                        family, coefficients)
                default: throw ProbeError.invalidRequest
                }
                try output(result)
            } catch { try output(["status": "error", "error": String(describing: error)]) }
        }
    } else {
        guard let count = Int(arguments[3]), (1...1_000_000).contains(count) else {
            throw ProbeError.invalidArguments
        }
        let begin = DispatchTime.now().uptimeNanoseconds
        var checksum = 0.0
        for index in 0..<count {
            let jd = 2_415_020.5 + Double(index) / Double(count) * (2_499_391.5 - 2_415_020.5)
            let state = try nativeState(jd, coefficients)
            checksum +=
                state.position.x + state.velocity.z + state.datePlane[2][1]
                + state.correctionSeconds
        }
        try output([
            "count": count, "evaluationNanoseconds": DispatchTime.now().uptimeNanoseconds - begin,
            "loadNanoseconds": loadNanoseconds, "peakRSSBytes": peakRSSBytes(),
            "checksum": checksum,
        ])
    }
}

do { try runIntegrated() } catch {
    FileHandle.standardError.write(Data("invalid integrated probe input: \(error)\n".utf8))
    exit(64)
}

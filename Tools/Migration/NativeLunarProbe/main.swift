import CoreFoundation
import Foundation

#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

// Development-only folded Moon-center minus Earth-center ICRF coefficients.
// This format is not SPK and is not used by the shipping package.
enum ProbeError: Error { case invalidData, invalidRequest, invalidArguments }

final class MappedBytes {
    let pointer: UnsafeMutableRawPointer
    let count: Int

    init(path: String) throws {
        let descriptor = open(path, O_RDONLY)
        guard descriptor >= 0 else { throw ProbeError.invalidData }
        defer { close(descriptor) }
        var status = stat()
        guard fstat(descriptor, &status) == 0, status.st_size >= 56,
            status.st_size <= 500_000_000,
            (status.st_mode & S_IFMT) == S_IFREG
        else { throw ProbeError.invalidData }
        count = Int(status.st_size)
        guard let mapped = mmap(nil, count, PROT_READ, MAP_PRIVATE, descriptor, 0),
            mapped != MAP_FAILED
        else { throw ProbeError.invalidData }
        pointer = mapped
    }

    deinit { munmap(pointer, count) }

    func integer(at offset: Int) -> UInt64 {
        UInt64(littleEndian: pointer.loadUnaligned(fromByteOffset: offset, as: UInt64.self))
    }

    func double(at offset: Int) -> Double { Double(bitPattern: integer(at: offset)) }
}

struct LunarCoefficients {
    let bytes: MappedBytes
    let recordCount: Int
    let coefficientCount: Int
    let startJD: Double
    let intervalDays: Double
    let lowerJD: Double
    let upperJD: Double

    init(path: String) throws {
        let mapped = try MappedBytes(path: path)
        guard
            (0..<8).allSatisfy({
                mapped.pointer.load(fromByteOffset: $0, as: UInt8.self)
                    == Array("MOONDEV1".utf8)[$0]
            }),
            (1...100_000).contains(mapped.integer(at: 8)),
            (1...65).contains(mapped.integer(at: 16))
        else { throw ProbeError.invalidData }
        bytes = mapped
        recordCount = Int(mapped.integer(at: 8))
        coefficientCount = Int(mapped.integer(at: 16))
        startJD = mapped.double(at: 24)
        intervalDays = mapped.double(at: 32)
        lowerJD = mapped.double(at: 40)
        upperJD = mapped.double(at: 48)
        let endJD = startJD + Double(recordCount) * intervalDays
        guard mapped.count == 56 + recordCount * 3 * coefficientCount * 8,
            [startJD, intervalDays, lowerJD, upperJD, endJD].allSatisfy(\.isFinite),
            intervalDays > 0, (intervalDays * 86_400).isFinite,
            (lowerJD - startJD).isFinite, (upperJD - startJD).isFinite,
            lowerJD >= startJD, upperJD <= endJD, lowerJD < upperJD
        else { throw ProbeError.invalidData }
        for offset in stride(from: 56, to: mapped.count, by: 8) {
            guard mapped.double(at: offset).isFinite else { throw ProbeError.invalidData }
        }
    }

    func state(tdb1: Double, tdb2: Double) throws -> (SIMD3<Double>, SIMD3<Double>) {
        guard tdb1.isFinite, tdb2.isFinite, abs(tdb1 - startJD) <= 10_000_000,
            abs(tdb2) <= 10_000_000
        else { throw ProbeError.invalidRequest }
        let elapsed = (tdb1 - startJD) + tdb2
        guard elapsed >= lowerJD - startJD, elapsed <= upperJD - startJD else {
            throw ProbeError.invalidRequest
        }
        // Keep split dates separate through seconds/remainders, as in the SPK evaluator.
        let intervalSeconds = intervalDays * 86_400
        func divide(_ value: Double) throws -> (Int, Double) {
            let quotient = floor(value / intervalSeconds)
            guard quotient.isFinite, quotient > Double(Int.min), quotient < Double(Int.max) else {
                throw ProbeError.invalidRequest
            }
            var remainder = value.truncatingRemainder(dividingBy: intervalSeconds)
            if remainder < 0 { remainder += intervalSeconds }
            return (Int(quotient), remainder)
        }
        let first = try divide((tdb1 - 2_451_545) * 86_400 - (startJD - 2_451_545) * 86_400)
        let second = try divide(tdb2 * 86_400)
        let combined = try divide(first.1 + second.1)
        let partial = first.0.addingReportingOverflow(second.0)
        let total = partial.partialValue.addingReportingOverflow(combined.0)
        guard !partial.overflow, !total.overflow else { throw ProbeError.invalidRequest }
        var record = total.partialValue
        var seconds = combined.1
        if record == recordCount {
            record -= 1
            seconds += intervalSeconds
        }
        guard (0..<recordCount).contains(record) else { throw ProbeError.invalidRequest }
        let s = 2 * seconds / intervalSeconds - 1
        var position = SIMD3<Double>(repeating: 0)
        var derivative = SIMD3<Double>(repeating: 0)
        for axis in 0..<3 {
            let offset = 56 + (record * 3 + axis) * coefficientCount * 8
            position[axis] = bytes.double(at: offset)
            var previous = 1.0
            var current = s
            var previousDerivative = 0.0
            var currentDerivative = 1.0
            for degree in 1..<coefficientCount {
                let coefficient = bytes.double(at: offset + degree * 8)
                position[axis] += coefficient * current
                derivative[axis] += coefficient * currentDerivative
                let next = 2 * s * current - previous
                let nextDerivative = 2 * current + 2 * s * currentDerivative - previousDerivative
                previous = current
                current = next
                previousDerivative = currentDerivative
                currentDerivative = nextDerivative
            }
        }
        return (position, derivative * (2 / intervalDays))
    }
}

func number(_ value: Any?) throws -> Double {
    guard let value = value as? NSNumber,
        CFGetTypeID(value) != CFBooleanGetTypeID(), value.doubleValue.isFinite
    else { throw ProbeError.invalidRequest }
    return value.doubleValue
}

func output(_ object: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

func peakRSSBytes() -> Int64 {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    #if canImport(Darwin)
        return Int64(usage.ru_maxrss)
    #else
        return Int64(usage.ru_maxrss) * 1024
    #endif
}

func run() throws {
    let arguments = CommandLine.arguments
    guard arguments.count >= 2 else { throw ProbeError.invalidArguments }
    if arguments[1] == "baseline", arguments.count == 2 {
        try output(["peakRSSBytes": peakRSSBytes(), "mode": "baseline"])
        return
    }
    guard
        (arguments[1] == "states" && arguments.count == 3)
            || (arguments[1] == "benchmark" && arguments.count == 4)
    else { throw ProbeError.invalidArguments }
    let start = DispatchTime.now().uptimeNanoseconds
    let coefficients = try LunarCoefficients(path: arguments[2])
    let loadNanoseconds = DispatchTime.now().uptimeNanoseconds - start
    if arguments[1] == "states" {
        while let line = readLine() {
            do {
                guard
                    let request = try JSONSerialization.jsonObject(with: Data(line.utf8))
                        as? [String: Any]
                else { throw ProbeError.invalidRequest }
                let state = try coefficients.state(
                    tdb1: number(request["tdb1"]), tdb2: number(request["tdb2"]))
                try output([
                    "request": request, "positionKm": [state.0.x, state.0.y, state.0.z],
                    "velocityKmPerDay": [state.1.x, state.1.y, state.1.z],
                ])
            } catch { try output(["error": String(describing: error)]) }
        }
    } else {
        guard let count = Int(arguments[3]), (1...10_000_000).contains(count) else {
            throw ProbeError.invalidArguments
        }
        var checksum = 0.0
        let evaluationStart = DispatchTime.now().uptimeNanoseconds
        for index in 0..<count {
            let fraction = Double(index) / Double(count)
            let offset =
                coefficients.lowerJD - 2_451_545 + fraction
                * (coefficients.upperJD - coefficients.lowerJD)
            let state = try coefficients.state(tdb1: 2_451_545, tdb2: offset)
            checksum += state.0.x + state.1.z
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - evaluationStart
        try output([
            "mode": "benchmark", "count": count, "loadNanoseconds": loadNanoseconds,
            "evaluationNanoseconds": elapsed, "checksum": checksum, "peakRSSBytes": peakRSSBytes(),
        ])
    }
}

do { try run() } catch {
    FileHandle.standardError.write(Data("invalid native probe input: \(error)\n".utf8))
    exit(64)
}

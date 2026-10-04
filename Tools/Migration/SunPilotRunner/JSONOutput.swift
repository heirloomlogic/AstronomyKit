#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum PilotOutputError: Error, Equatable {
    case nonfiniteNumber
    case invalidClock
    case systemClock
    case outputWriteFailed(Int32)
    case outputNoProgress
}

enum PilotJSON {
    static func number(_ value: Double) throws -> String {
        guard value.isFinite else { throw PilotOutputError.nonfiniteNumber }
        return String(value)
    }

    static func string(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22: result += "\\\""
            case 0x5c: result += "\\\\"
            case 0..<0x20:
                let digits = String(scalar.value, radix: 16)
                result += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
            default: result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }

    static func object(_ fields: [String: String]) -> String {
        "{"
            + fields.sorted { $0.key < $1.key }.map { string($0.key) + ":" + $0.value }.joined(
                separator: ",") + "}"
    }
}

extension Sample {
    func json() throws -> String {
        var fields = ["status": PilotJSON.string(status)]
        for (key, value) in [
            ("ut", ut), ("tt", tt), ("x", x), ("y", y), ("z", z),
            ("gx", gx), ("gy", gy), ("gz", gz), ("ra", ra), ("dec", dec),
            ("distance", distance), ("altitude", altitude),
        ] {
            if let value { fields[key] = try PilotJSON.number(value) }
        }
        if let fallback { fields["fallback"] = fallback ? "true" : "false" }
        if let iterations { fields["iterations"] = String(iterations) }
        if let fallbackEvaluations { fields["fallbackEvaluations"] = String(fallbackEvaluations) }
        return PilotJSON.object(fields)
    }
}

extension Runner.Workload {
    func json() throws -> String {
        PilotJSON.object([
            "operations": String(operations), "elapsedNanoseconds": String(elapsedNanoseconds),
            "checksum": try PilotJSON.number(checksum),
        ])
    }
}

enum PilotClock {
    static func nanoseconds(seconds: Int64, nanoseconds: Int64) throws -> UInt64 {
        guard seconds >= 0, nanoseconds >= 0, nanoseconds < 1_000_000_000 else {
            throw PilotOutputError.invalidClock
        }
        let (whole, multiplyOverflow) = UInt64(seconds).multipliedReportingOverflow(by: 1_000_000_000)
        let (result, addOverflow) = whole.addingReportingOverflow(UInt64(nanoseconds))
        guard !multiplyOverflow && !addOverflow else { throw PilotOutputError.invalidClock }
        return result
    }

    static func now() throws -> UInt64 {
        var time = timespec()
        guard clock_gettime(CLOCK_MONOTONIC, &time) == 0 else { throw PilotOutputError.systemClock }
        return try nanoseconds(seconds: Int64(time.tv_sec), nanoseconds: Int64(time.tv_nsec))
    }
}

enum PilotOutput {
    static func line(_ text: String) throws {
        let bytes = Array((text + "\n").utf8)
        try bytes.withUnsafeBytes { buffer in
            try writeAll(buffer) { address, count in
                write(STDOUT_FILENO, address, count)
            }
        }
    }

    static func writeAll(
        _ bytes: UnsafeRawBufferPointer, using writer: (UnsafeRawPointer, Int) -> Int
    ) throws {
        guard let start = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let count = writer(start.advanced(by: offset), bytes.count - offset)
            if count < 0 {
                let failure = errno
                if failure == EINTR { continue }
                throw PilotOutputError.outputWriteFailed(failure)
            }
            guard count > 0 else { throw PilotOutputError.outputNoProgress }
            offset += count
        }
    }
}

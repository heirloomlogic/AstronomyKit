//
//  EngineTables.swift
//  AstronomyKit
//
//  What the modules with compiled-in model data share: how the generated
//  tables are stored, and the time range the ephemerides accept.
//

import Foundation

extension Engine {
    /// The largest |TT| in days that the planet and Moon functions accept:
    /// 4,000 Julian years either side of J2000, the span over which VSOP87
    /// states 1″ precision for Mercury to Mars.
    static let acceptedTTDays = 1_461_000.0

    /// Throws `AstronomyError.badTime` when |TT| of `time` is above
    /// ``acceptedTTDays`` or is not finite.
    static func checkAcceptedTime(_ time: Engine.Time) throws {
        guard abs(time.tt) <= acceptedTTDays else { throw AstronomyError.badTime }
    }

    /// Decodes `count` doubles from `text`, the base64 of their little-endian
    /// IEEE 754 bit patterns. Characters outside the base64 alphabet, such as
    /// line breaks, are skipped.
    ///
    /// The generated tables are string literals because array literals do
    /// not scale: one of 100,002 doubles took the compiler 390 s in a Debug
    /// build, and the planet tables hold 1.5 million. Each table calls this
    /// from a `static let` initializer, so it is decoded once, on first use.
    /// Traps when `text` does not hold exactly `count` doubles, which only a
    /// damaged generated file can cause.
    static func unpackDoubles(count: Int, _ text: StaticString) -> [Double] {
        // A string literal lives for the whole process, so its bytes need no copy.
        let data = text.withUTF8Buffer { utf8 -> Data? in
            guard let base = utf8.baseAddress else { return Data() }
            let literal = Data(
                bytesNoCopy: UnsafeMutableRawPointer(mutating: base), count: utf8.count, deallocator: .none)
            return Data(base64Encoded: literal, options: .ignoreUnknownCharacters)
        }
        guard let data, data.count == count * 8 else {
            preconditionFailure("A generated table does not hold \(count) doubles")
        }
        return data.withUnsafeBytes { raw in
            (0..<count).map { index in
                Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)))
            }
        }
    }
}

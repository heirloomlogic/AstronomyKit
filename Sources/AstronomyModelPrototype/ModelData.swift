import AstronomyModelPrototypeGenerated
import AstronomyNutationPrototype
import AstronomyPolynomialEarthPrototype
import AstronomyPolynomialJupiterPrototype
import AstronomyPolynomialMarsPrototype
import AstronomyPolynomialMercuryPrototype
import AstronomyPolynomialNeptunePrototype
import AstronomyPolynomialSaturnPrototype
import AstronomyPolynomialUranusPrototype
import AstronomyPolynomialVenusPrototype
import AstronomyVSOPPrototype

/// A body represented by the generated polynomial tables.
public enum PrototypeBody: Int, CaseIterable, Sendable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune
}

/// The grid and archive identity for one body's polynomial table.
public struct PolynomialMetadata: Sendable {
    /// The model name used by the frozen archive.
    public let name: String
    /// The inclusive lower TT bound of the shared polynomial grid.
    public let startTT: Double
    /// The exclusive upper TT bound of the shared polynomial grid.
    public let stopTT: Double
    /// The degree of each coordinate polynomial.
    public let degree: Int
    /// The number of TT days represented by one segment.
    public let width: Int
    /// The number of segments in this body's table.
    public let segments: Int
    /// The number of binary64 coefficient bit patterns in this body's table.
    public let coefficientCount: Int
    /// The SHA-256 digest of the frozen coefficient bytes.
    public let coefficientSHA256: String
    /// The SHA-256 digest of the effective validity bytes.
    public let validitySHA256: String
}

/// The index range for one VSOP coordinate and time power.
public struct VSOPSeriesMetadata: Sendable {
    /// The zero-based body index from the frozen VSOP archive.
    public let body: Int
    /// The zero-based coordinate index.
    public let coordinate: Int
    /// The time power used by this series.
    public let power: Int
    /// The first term index in the flattened term table.
    public let offset: Int
    /// The number of terms in this series.
    public let count: Int
}

/// One IAU 2000B nutation row represented as exact integer and binary64 bits.
public struct NutationRow: Sendable {
    /// The five integer fundamental-argument multipliers.
    public let multipliers: [Int64]
    /// The six binary64 coefficient bit patterns.
    public let coefficientBits: [UInt64]
}

/// Access to the complete generated model prototype.
public enum PrototypeModelData {
    /// Metadata for every generated polynomial body in ``PrototypeBody`` order.
    public static var polynomialMetadata: [PolynomialMetadata] {
        generatedPolynomialMetadata.map {
            PolynomialMetadata(
                name: $0.name,
                startTT: $0.startTT,
                stopTT: $0.stopTT,
                degree: $0.degree,
                width: $0.width,
                segments: $0.segments,
                coefficientCount: $0.coefficientCount,
                coefficientSHA256: $0.coefficientSHA256,
                validitySHA256: $0.validitySHA256
            )
        }
    }

    /// Metadata for every flattened VSOP series.
    public static var vsopSeries: [VSOPSeriesMetadata] {
        generatedVSOPSeries.map {
            VSOPSeriesMetadata(
                body: $0.body, coordinate: $0.coordinate, power: $0.power, offset: $0.offset,
                count: $0.count)
        }
    }

    /// The number of terms in the flattened VSOP table.
    public static var vsopTermCount: Int { generatedVSOPTermCount }

    /// The number of rows in the IAU 2000B nutation table.
    public static var nutationRowCount: Int { nutationIntegerBits.count / 5 }

    /// The number of polynomial segments that use the fallback representation.
    public static var disabledPolynomialSegmentCount: Int {
        PrototypeBody.allCases.reduce(into: 0) { count, body in
            count += generatedPolynomialValidity(body: body).count(where: { $0 == 0 })
        }
    }

    /// Returns the exact coefficient bit pattern at `index`, or `nil` when the index is outside the selected body's table.
    public static func polynomialBitPattern(body: PrototypeBody, index: Int) -> UInt64? {
        switch body {
        case .mercury: polynomialMercuryBitPattern(at: index)
        case .venus: polynomialVenusBitPattern(at: index)
        case .earth: polynomialEarthBitPattern(at: index)
        case .mars: polynomialMarsBitPattern(at: index)
        case .jupiter: polynomialJupiterBitPattern(at: index)
        case .saturn: polynomialSaturnBitPattern(at: index)
        case .uranus: polynomialUranusBitPattern(at: index)
        case .neptune: polynomialNeptuneBitPattern(at: index)
        }
    }

    /// Returns the validity bit for a polynomial segment, or `nil` when the segment is outside the selected body's grid.
    public static func polynomialValidity(body: PrototypeBody, segment: Int) -> Bool? {
        let values = generatedPolynomialValidity(body: body)
        guard values.indices.contains(segment) else { return nil }
        return values[segment] != 0
    }

    /// Returns the exact bit patterns for a VSOP term, or `nil` when `index` is outside the term table.
    public static func vsopTermBitPatterns(
        at index: Int
    ) -> (
        amplitude: UInt64, phase: UInt64, frequency: UInt64
    )? {
        guard index >= 0, index < generatedVSOPTermCount else { return nil }
        let offset = index * 3
        guard let amplitude = vsopTermBitPattern(at: offset),
            let phase = vsopTermBitPattern(at: offset + 1),
            let frequency = vsopTermBitPattern(at: offset + 2)
        else { return nil }
        return (amplitude, phase, frequency)
    }

    /// Returns one nutation row, or `nil` when `index` is outside the table.
    public static func nutationRow(at index: Int) -> NutationRow? {
        guard index >= 0, index < nutationIntegerBits.count / 5,
            index < nutationCoefficientBits.count / 6
        else { return nil }
        let integerOffset = index * 5
        let coefficientOffset = index * 6
        return NutationRow(
            multipliers: nutationIntegerBits[integerOffset..<integerOffset + 5].map(
                Int64.init(bitPattern:)),
            coefficientBits: Array(nutationCoefficientBits[coefficientOffset..<coefficientOffset + 6]))
    }

    /// Computes the FNV-1a checksum over every generated table in archive order.
    public static func wholeModelFNV64() -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func include(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        for body in PrototypeBody.allCases {
            for index in 0..<polynomialMetadata[body.rawValue].coefficientCount {
                guard let bitPattern = polynomialBitPattern(body: body, index: index) else {
                    preconditionFailure("Generated polynomial metadata exceeds its coefficient table")
                }
                include(bitPattern)
            }
            for value in generatedPolynomialValidity(body: body) { include(UInt64(value)) }
        }
        for index in 0..<generatedVSOPTermCount * 3 {
            guard let value = vsopTermBitPattern(at: index) else {
                preconditionFailure("Generated VSOP metadata exceeds its coefficient table")
            }
            include(value)
        }
        for series in generatedVSOPSeries {
            include(UInt64(series.body))
            include(UInt64(series.coordinate))
            include(UInt64(series.power))
            include(UInt64(series.offset))
            include(UInt64(series.count))
        }
        for row in 0..<nutationRowCount {
            for value in nutationIntegerBits[row * 5..<row * 5 + 5] { include(value) }
            for value in nutationCoefficientBits[row * 6..<row * 6 + 6] { include(value) }
        }
        return hash
    }
}

private func generatedPolynomialValidity(body: PrototypeBody) -> [UInt8] {
    switch body {
    case .mercury: polynomialMercuryValidity
    case .venus: polynomialVenusValidity
    case .earth: polynomialEarthValidity
    case .mars: polynomialMarsValidity
    case .jupiter: polynomialJupiterValidity
    case .saturn: polynomialSaturnValidity
    case .uranus: polynomialUranusValidity
    case .neptune: polynomialNeptuneValidity
    }
}

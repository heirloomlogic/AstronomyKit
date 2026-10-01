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

public enum PrototypeBody: Int, CaseIterable, Sendable {
    case mercury, venus, earth, mars, jupiter, saturn, uranus, neptune
}

public struct PolynomialMetadata: Sendable {
    public let name: String
    public let degree: Int
    public let width: Int
    public let segments: Int
    public let coefficientCount: Int
    public let coefficientSHA256: String
    public let validitySHA256: String
}

public struct VSOPSeriesMetadata: Sendable {
    public let body: Int
    public let coordinate: Int
    public let power: Int
    public let offset: Int
    public let count: Int
}

public struct NutationRow: Sendable {
    public let multipliers: [Int64]
    public let coefficientBits: [UInt64]
}

public enum PrototypeModelData {
    public static var polynomialMetadata: [PolynomialMetadata] { generatedPolynomialMetadata }

    public static var vsopSeries: [VSOPSeriesMetadata] {
        generatedVSOPSeries.map { VSOPSeriesMetadata(body: $0.body, coordinate: $0.coordinate, power: $0.power, offset: $0.offset, count: $0.count) }
    }

    public static var vsopTermCount: Int { vsopTermBits.count / 3 }

    public static var nutationRowCount: Int { nutationIntegerBits.count / 5 }

    public static var disabledPolynomialSegmentCount: Int {
        PrototypeBody.allCases.reduce(into: 0) { count, body in
            count += generatedPolynomialValidity(body: body).count(where: { $0 == 0 })
        }
    }

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

    public static func polynomialValidity(body: PrototypeBody, segment: Int) -> Bool? {
        let values = generatedPolynomialValidity(body: body)
        guard values.indices.contains(segment) else { return nil }
        return values[segment] != 0
    }

    public static func vsopTermBitPatterns(at index: Int) -> (amplitude: UInt64, phase: UInt64, frequency: UInt64)? {
        let offset = index * 3
        guard index >= 0, offset + 2 < vsopTermBits.count else { return nil }
        return (vsopTermBits[offset], vsopTermBits[offset + 1], vsopTermBits[offset + 2])
    }

    public static func nutationRow(at index: Int) -> NutationRow? {
        let integerOffset = index * 5
        let coefficientOffset = index * 6
        guard index >= 0, integerOffset + 4 < nutationIntegerBits.count, coefficientOffset + 5 < nutationCoefficientBits.count else { return nil }
        return NutationRow(multipliers: nutationIntegerBits[integerOffset ..< integerOffset + 5].map(Int64.init(bitPattern:)), coefficientBits: Array(nutationCoefficientBits[coefficientOffset ..< coefficientOffset + 6]))
    }

    public static func wholeModelFNV64() -> UInt64 {
        var hash: UInt64 = 14_695_981_039_346_656_037
        func include(_ value: UInt64) { hash = (hash ^ value) &* 1_099_511_628_211 }
        for body in PrototypeBody.allCases {
            for index in 0 ..< polynomialMetadata[body.rawValue].coefficientCount { include(polynomialBitPattern(body: body, index: index)!) }
            for value in generatedPolynomialValidity(body: body) { include(UInt64(value)) }
        }
        for value in vsopTermBits { include(value) }
        for series in generatedVSOPSeries {
            include(UInt64(series.body))
            include(UInt64(series.coordinate))
            include(UInt64(series.power))
            include(UInt64(series.offset))
            include(UInt64(series.count))
        }
        for row in 0 ..< nutationRowCount {
            for value in nutationIntegerBits[row * 5 ..< row * 5 + 5] { include(value) }
            for value in nutationCoefficientBits[row * 6 ..< row * 6 + 6] { include(value) }
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

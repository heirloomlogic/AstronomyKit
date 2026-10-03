// Adapted from Astronomy Engine; its MIT notice is retained in THIRD_PARTY_NOTICES.
import Foundation

/// Equatorial J2000 Cartesian coordinates in astronomical units.
public struct PilotVector: Sendable {
    /// The X coordinate in AU.
    public let x: Double
    /// The Y coordinate in AU.
    public let y: Double
    /// The Z coordinate in AU.
    public let z: Double

    var length: Double { sqrt(x * x + y * y + z * z) }
    static func - (lhs: Self, rhs: Self) -> Self {
        Self(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }
    var negative: Self { Self(x: -x, y: -y, z: -z) }
}

/// Earth position and the model branch used to evaluate it.
public struct PilotEarth: Sendable {
    /// Heliocentric Earth position in the J2000 equatorial frame.
    public let vector: PilotVector
    /// Whether the complete compensated VSOP series was evaluated.
    public let usedFallback: Bool
    /// The grid segment, or nil outside polynomial coverage or when full series is forced.
    public let segment: Int?
}

/// A development evaluator using the frozen Earth tables and expression order.
public enum SunPilot {
    static let earthMetadata = PrototypeModelData.polynomialMetadata[PrototypeBody.earth.rawValue]
    static let earthSeries = (0..<3).map { coordinate in
        PrototypeModelData.vsopSeries.filter {
            $0.body == PrototypeBody.earth.rawValue && $0.coordinate == coordinate
        }
    }

    /// Evaluates Earth at explicit TT; the amplitude scale is a development negative control.
    public static func earth(
        tt: Double, forceFullSeries: Bool = false, fullSeriesAmplitudeScale: Double = 1
    ) throws -> PilotEarth {
        guard tt.isFinite && abs(tt) <= 1_461_000 else { throw PilotError.badTime }
        let metadata = earthMetadata
        var segment: Int?
        var eclip: PilotVector?
        if !forceFullSeries && tt >= metadata.startTT && tt < metadata.stopTT {
            var index = Int((tt - metadata.startTT) / Double(metadata.width))
            if index > 0 && metadata.startTT + Double(index * metadata.width) > tt { index -= 1 }
            segment = index
            if PrototypeModelData.polynomialValidity(body: .earth, segment: index) == true {
                let start = metadata.startTT + Double(index * metadata.width)
                let half = Double(metadata.width / 2)
                let x = (tt - start) / half - 1
                let n = metadata.degree + 1
                func coordinate(_ axis: Int) -> Double {
                    let offset = index * 3 * n + axis * n
                    var b1 = 0.0
                    var b2 = 0.0
                    for k in stride(from: metadata.degree, through: 1, by: -1) {
                        let a = earthCoefficient(at: offset + k)
                        let b = 2 * x * b1 - b2 + a
                        b2 = b1
                        b1 = b
                    }
                    return x * b1 - b2
                        + earthCoefficient(at: offset)
                }
                eclip = PilotVector(x: coordinate(0), y: coordinate(1), z: coordinate(2))
            }
        }
        let fallback = eclip == nil
        let p = eclip ?? fullEarth(tt: tt, amplitudeScale: fullSeriesAmplitudeScale)
        return PilotEarth(
            vector: PilotVector(
                x: p.x + 0.000000440360 * p.y - 0.000000190919 * p.z,
                y: -0.000000479966 * p.x + 0.917482137087 * p.y - 0.397776982902 * p.z,
                z: 0.397776982902 * p.y + 0.917482137087 * p.z),
            usedFallback: fallback, segment: segment)
    }

    static func earthCoefficient(at index: Int) -> Double {
        guard let bits = PrototypeModelData.polynomialBitPattern(body: .earth, index: index) else {
            preconditionFailure("Generated Earth metadata exceeds its coefficient table")
        }
        return Double(bitPattern: bits)
    }

    static func compensatedAdd(_ sum: inout Double, _ compensation: inout Double, _ value: Double) {
        let next = sum + value
        compensation += abs(sum) >= abs(value) ? ((sum - next) + value) : ((value - next) + sum)
        sum = next
    }

    static func fullEarth(tt: Double, amplitudeScale: Double) -> PilotVector {
        let t = tt / 365250.0
        func coordinate(_ axis: Int) -> Double {
            var power = 1.0
            var total = 0.0
            var totalCompensation = 0.0
            for series in earthSeries[axis] {
                var sum = 0.0
                var compensation = 0.0
                for index in series.offset..<series.offset + series.count {
                    guard let bits = PrototypeModelData.vsopTermBitPatterns(at: index) else {
                        preconditionFailure("Generated Earth VSOP metadata exceeds its term table")
                    }
                    let amplitude = Double(bitPattern: bits.amplitude) * amplitudeScale
                    let phase = Double(bitPattern: bits.phase)
                    let frequency = Double(bitPattern: bits.frequency)
                    compensatedAdd(&sum, &compensation, amplitude * cos(phase + t * frequency))
                }
                sum += compensation
                var increment = power * sum
                if axis == 0 { increment = increment.truncatingRemainder(dividingBy: 2 * .pi) }
                compensatedAdd(&total, &totalCompensation, increment)
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
}

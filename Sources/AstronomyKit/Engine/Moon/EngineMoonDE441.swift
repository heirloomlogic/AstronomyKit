import Foundation

extension Engine {
    /// The qualified DE441 shared-endpoint quintics; coefficients and nodes are geometric ICRF kilometers and TDB-day rates.
    enum MoonDE441 {}
}

extension Engine.MoonDE441 {
    static func evaluate(tdb: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tdb.isFinite, tdb >= start else { return nil }
        let offset = tdb - start
        let interval = offset / 4
        guard interval < Double(recordCount) else { return nil }
        let record = Int(interval.rounded(.down))
        return evaluate(record: record, x: (offset - Double(record) * 4) / 2 - 1)
    }

    /// Reconstructs one quintic from its shared endpoint states and c4/c5, then returns AU and AU per TDB day.
    static func evaluate(record: Int, x: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        precondition((0..<recordCount).contains(record))
        return data.withUnsafeBytes { raw in
            func value(_ offset: Int) -> Double {
                Double(
                    Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
            }
            let right = 24 + record * 48
            let left = record == 0 ? 0 : right - 48
            var position = SIMD3<Double>()
            var velocity = SIMD3<Double>()
            for axis in 0..<3 {
                let pl = value(left + axis * 4)
                let vl = value(left + (axis + 3) * 4)
                let pr = value(right + axis * 4)
                let vr = value(right + (axis + 3) * 4)
                let c4 = value(right + 24 + axis * 8)
                let c5 = value(right + 28 + axis * 8)
                let even = (pr + pl) / 2
                let odd = (pr - pl) / 2
                let c2 = (vr - vl - 16 * c4) / 4
                let c3 = (vr + vl - odd - 24 * c5) / 8
                let coefficients = [even - c2 - c4, odd - c3 - c5, c2, c3, c4, c5]
                var (b1, b2, d1, d2) = (0.0, 0.0, 0.0, 0.0)
                for k in stride(from: 5, to: 0, by: -1) {
                    let b = 2 * x * b1 - b2 + coefficients[k]
                    let d = 2 * b1 + 2 * x * d1 - d2
                    (b2, b1) = (b1, b)
                    (d2, d1) = (d1, d)
                }
                position[axis] = (coefficients[0] + x * b1 - b2) / Engine.kilometersPerAU
                velocity[axis] = (b1 + x * d1 - d2) / (2 * Engine.kilometersPerAU)
            }
            return (position, velocity)
        }
    }

    /// Transforms the ICRF/TDB polynomial state into EQJ coordinates with rates per TT day.
    static func state(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay
        guard let source = evaluate(tdb: tdb) else { return nil }
        let bias = Engine.FrameBias.icrsToEqj
        return (bias.apply(to: source.position), bias.apply(to: source.velocity * Engine.TDB.rate(tt: tt)))
    }

    static func position(tt: Double) -> SIMD3<Double>? {
        guard tt.isFinite else { return nil }
        let tdb = tt + Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay
        return evaluate(tdb: tdb).map { Engine.FrameBias.icrsToEqj.apply(to: $0.position) }
    }
}

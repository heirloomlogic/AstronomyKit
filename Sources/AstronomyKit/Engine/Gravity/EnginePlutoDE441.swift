import Foundation

extension Engine {
    /// DE441's Pluto-system barycenter relative to the Sun; the physical Pluto-center offset is absent.
    enum PlutoDE441 {}
}

extension Engine.PlutoDE441 {
    static let acceptedTTDays = Engine.acceptedTTDays

    /// Shared endpoint positions in ICRF km and analytic derivatives in km per TDB day.
    struct Table: Sendable {
        let start: Double
        let days: Double
        let recordCount: Int
        let data: Engine.MappedBytes

        init(start: Double, days: Double, recordCount: Int, resource: Engine.TableResource) {
            precondition(days > 0 && recordCount > 0)
            precondition(resource.byteCount == (recordCount + 1) * 6 * 8)
            self.start = start
            self.days = days
            self.recordCount = recordCount
            self.data = Engine.MappedBytes.bundled(resource)
        }

        private func locate(tdb: Double) -> (record: Int, x: Double)? {
            let end = start + Double(recordCount) * days
            guard tdb.isFinite, end.isFinite, tdb >= start, tdb < end else { return nil }
            let interval = (tdb - start) / days
            guard interval.isFinite else { return nil }
            var record = min(max(Int(interval.rounded(.down)), 0), recordCount - 1)
            if record > 0, tdb < start + Double(record) * days { record -= 1 }
            if record < recordCount - 1, tdb >= start + Double(record + 1) * days { record += 1 }
            let rawX = 2 * (tdb - (start + Double(record) * days)) / days - 1
            guard rawX.isFinite else { return nil }
            return (record, min(max(rawX, -1.0), 1.0))
        }

        func evaluate(tdb: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
            guard let located = locate(tdb: tdb) else { return nil }
            return evaluate(record: located.record, x: located.x)
        }

        /// Reconstructs the cubic position (AU), velocity (AU/TDB day), and acceleration (AU/TDB day²) in one pass,
        /// sharing identical position and velocity bits with ``evaluate(tdb:)``.
        func evaluateWithAcceleration(
            tdb: Double
        ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>, acceleration: SIMD3<Double>)? {
            guard let located = locate(tdb: tdb) else { return nil }
            return evaluateWithAcceleration(record: located.record, x: located.x)
        }

        /// Reconstructs the cubic and returns AU and AU per TDB day.
        func evaluate(record: Int, x: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
            precondition((0..<recordCount).contains(record))
            return data.withUnsafeBytes { raw in
                @inline(__always)
                func value(_ offset: Int) -> Double {
                    Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
                }
                let left = record * 48
                let right = left + 48
                let twoX = 2 * x
                let halfDays = days / 2
                let invKmPerAU = 1 / Engine.kilometersPerAU
                let velScale = 2 / (days * Engine.kilometersPerAU)
                var position = SIMD3<Double>()
                var velocity = SIMD3<Double>()
                for axis in 0..<3 {
                    let pl = value(left + axis * 8)
                    let pr = value(right + axis * 8)
                    let dl = value(left + (axis + 3) * 8) * halfDays
                    let dr = value(right + (axis + 3) * 8) * halfDays
                    let even = (pr + pl) / 2
                    let odd = (pr - pl) / 2
                    let c2 = (dr - dl) / 8
                    let c3 = (dr + dl - 2 * odd) / 16
                    let c0 = even - c2
                    let c1 = odd - c3
                    // Unrolled degree-3 Clenshaw recurrence (zero heap allocation).
                    let b3 = c3
                    let b2 = twoX * b3 + c2
                    let d2 = 2 * b3
                    let b1 = twoX * b2 - b3 + c1
                    let d1 = 2 * b2 + twoX * d2
                    position[axis] = (c0 + x * b1 - b2) * invKmPerAU
                    velocity[axis] = (b1 + x * d1 - d2) * velScale
                }
                return (position, velocity)
            }
        }

        func evaluateWithAcceleration(
            record: Int, x: Double
        ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>, acceleration: SIMD3<Double>) {
            precondition((0..<recordCount).contains(record))
            return data.withUnsafeBytes { raw in
                @inline(__always)
                func value(_ offset: Int) -> Double {
                    Double(bitPattern: UInt64(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
                }
                let left = record * 48
                let right = left + 48
                let twoX = 2 * x
                let halfDays = days / 2
                let invKmPerAU = 1 / Engine.kilometersPerAU
                let velScale = 2 / (days * Engine.kilometersPerAU)
                let accScale = 4 / (days * days * Engine.kilometersPerAU)
                var position = SIMD3<Double>()
                var velocity = SIMD3<Double>()
                var acceleration = SIMD3<Double>()
                for axis in 0..<3 {
                    let pl = value(left + axis * 8)
                    let pr = value(right + axis * 8)
                    let dl = value(left + (axis + 3) * 8) * halfDays
                    let dr = value(right + (axis + 3) * 8) * halfDays
                    let even = (pr + pl) / 2
                    let odd = (pr - pl) / 2
                    let c2 = (dr - dl) / 8
                    let c3 = (dr + dl - 2 * odd) / 16
                    let c0 = even - c2
                    let c1 = odd - c3
                    let b3 = c3
                    let b2 = twoX * b3 + c2
                    let d2 = 2 * b3
                    let b1 = twoX * b2 - b3 + c1
                    let d1 = 2 * b2 + twoX * d2
                    position[axis] = (c0 + x * b1 - b2) * invKmPerAU
                    velocity[axis] = (b1 + x * d1 - d2) * velScale
                    acceleration[axis] = (4 * c2 + 24 * x * c3) * accScale
                }
                return (position, velocity, acceleration)
            }
        }
    }

    /// Transforms the heliocentric barycenter state from ICRF/TDB into EQJ with rates per TT day.
    static func state(tt: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite, abs(tt) <= acceptedTTDays else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let p = pluto.evaluate(tdb: tdb), let s = sun.evaluate(tdb: tdb) else { return nil }
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: p.position - s.position),
            bias.apply(to: (p.velocity - s.velocity) * conversion.rate)
        )
    }
}

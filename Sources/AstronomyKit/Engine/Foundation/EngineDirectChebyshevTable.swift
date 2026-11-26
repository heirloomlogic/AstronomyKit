import Foundation

extension Engine {
    /// Direct type-2 SPK coefficients with their source record grid and scalar encoding.
    struct DirectChebyshevTable: Sendable {
        let start: Double
        let days: Double
        let recordCount: Int
        let coefficientCount: Int
        let scalarBytes: Int
        let data: Data
        private let mappedData: Engine.MappedBytes?
        private let recordsPerChunk: Int
        private let chunks: [StaticString]

        var byteCount: Int {
            if let mappedData { return mappedData.count }
            if !chunks.isEmpty { return recordCount * 3 * coefficientCount * scalarBytes }
            return data.count
        }

        private static let base64LUT: [UInt8] = {
            var table = [UInt8](repeating: 0xff, count: 256)
            for c in UInt8(65)...90 { table[Int(c)] = c - 65 }
            for c in UInt8(97)...122 { table[Int(c)] = c - 71 }
            for c in UInt8(48)...57 { table[Int(c)] = c + 4 }
            table[43] = 62
            table[47] = 63
            return table
        }()

        init(start: Double, days: Double, recordCount: Int, coefficientCount: Int, scalarBytes: Int, data: Data) {
            precondition(days > 0 && recordCount > 0 && coefficientCount > 0)
            precondition(scalarBytes == 4 || scalarBytes == 8)
            precondition(data.count == recordCount * 3 * coefficientCount * scalarBytes)
            self.start = start
            self.days = days
            self.recordCount = recordCount
            self.coefficientCount = coefficientCount
            self.scalarBytes = scalarBytes
            self.data = data
            self.mappedData = nil
            self.recordsPerChunk = 0
            self.chunks = []
        }

        init(
            start: Double, days: Double, recordCount: Int, coefficientCount: Int, scalarBytes: Int,
            resource: Engine.TableResource
        ) {
            precondition(days > 0 && recordCount > 0 && coefficientCount > 0)
            precondition(scalarBytes == 4 || scalarBytes == 8)
            precondition(resource.byteCount == recordCount * 3 * coefficientCount * scalarBytes)
            self.start = start
            self.days = days
            self.recordCount = recordCount
            self.coefficientCount = coefficientCount
            self.scalarBytes = scalarBytes
            self.data = Data()
            self.mappedData = Engine.MappedBytes.bundled(resource)
            self.recordsPerChunk = 0
            self.chunks = []
        }

        init(
            start: Double, days: Double, recordCount: Int, coefficientCount: Int, scalarBytes: Int,
            data: Engine.MappedBytes
        ) {
            precondition(days > 0 && recordCount > 0 && coefficientCount > 0)
            precondition(scalarBytes == 4 || scalarBytes == 8)
            precondition(data.count == recordCount * 3 * coefficientCount * scalarBytes)
            self.start = start
            self.days = days
            self.recordCount = recordCount
            self.coefficientCount = coefficientCount
            self.scalarBytes = scalarBytes
            self.data = Data()
            self.mappedData = data
            self.recordsPerChunk = 0
            self.chunks = []
        }

        init(
            start: Double, days: Double, recordCount: Int, coefficientCount: Int,
            recordsPerChunk: Int, chunks: [StaticString]
        ) {
            precondition(days > 0 && recordCount > 0 && coefficientCount > 0)
            precondition(recordsPerChunk > 0 && chunks.count == (recordCount + recordsPerChunk - 1) / recordsPerChunk)
            self.start = start
            self.days = days
            self.recordCount = recordCount
            self.coefficientCount = coefficientCount
            self.scalarBytes = 8
            self.data = Data()
            self.mappedData = nil
            self.recordsPerChunk = recordsPerChunk
            self.chunks = chunks
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
            guard let (record, x) = locate(tdb: tdb) else { return nil }
            return evaluate(record: record, x: x)
        }

        func acceleration(tdb: Double) -> SIMD3<Double>? {
            guard let (record, x) = locate(tdb: tdb) else { return nil }
            return acceleration(record: record, x: x)
        }

        func evaluateAndAcceleration(
            tdb: Double
        ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>, acceleration: SIMD3<Double>)? {
            guard let (record, x) = locate(tdb: tdb) else { return nil }
            return withCoefficients(record: record, x: x) { localRecord, localX, coefficient in
                evaluateAndAcceleration(record: localRecord, x: localX, coefficient: coefficient)
            }
        }

        /// Clenshaw value and analytic derivative, in source units per TDB day.
        func evaluate(record: Int, x: Double) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
            precondition((0..<recordCount).contains(record) && x.isFinite && (-1...1).contains(x))
            return withCoefficients(record: record, x: x) { localRecord, localX, coefficient in
                evaluate(record: localRecord, x: localX, coefficient: coefficient)
            }
        }

        /// Analytic second derivative in source units per TDB day squared.
        func acceleration(record: Int, x: Double) -> SIMD3<Double>? {
            precondition((0..<recordCount).contains(record) && x.isFinite && (-1...1).contains(x))
            return withCoefficients(record: record, x: x) { localRecord, localX, coefficient in
                acceleration(record: localRecord, x: localX, coefficient: coefficient)
            }
        }

        private func withCoefficients<Result>(
            record: Int, x: Double, body: (Int, Double, (Int) -> Double) -> Result
        ) -> Result? {
            if chunks.isEmpty {
                return withRawBytes { raw in
                    body(record, x) { index in
                        let offset = index * scalarBytes
                        if scalarBytes == 4 {
                            return Double(
                                Float(
                                    bitPattern: UInt32(
                                        littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self))))
                        }
                        return Double(
                            bitPattern: UInt64(
                                littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)))
                    }
                }
            }
            let local = record % recordsPerChunk
            let encodedRecordBytes = coefficientCount * 32
            return chunks[record / recordsPerChunk].withUTF8Buffer { bytes in
                let base = local * (encodedRecordBytes + 1)
                guard base + encodedRecordBytes <= bytes.count else { return nil }
                return Self.base64LUT.withUnsafeBufferPointer { lut in
                    withUnsafeTemporaryAllocation(of: Double.self, capacity: 3 * coefficientCount) { coefficients in
                        withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 3 * coefficientCount * 8) { decoded in
                            var src = base
                            var dst = 0
                            let srcEnd = base + encodedRecordBytes
                            while src < srcEnd {
                                let s0 = lut[Int(bytes[src])]
                                let s1 = lut[Int(bytes[src + 1])]
                                let s2 = lut[Int(bytes[src + 2])]
                                let s3 = lut[Int(bytes[src + 3])]
                                guard (s0 | s1 | s2 | s3) < 64 else { return nil }
                                decoded[dst] = (s0 << 2) | (s1 >> 4)
                                decoded[dst + 1] = (s1 << 4) | (s2 >> 2)
                                decoded[dst + 2] = (s2 << 6) | s3
                                src += 4
                                dst += 3
                            }
                            let decodedRaw = UnsafeRawBufferPointer(decoded)
                            for index in coefficients.indices {
                                let bits = UInt64(
                                    littleEndian: decodedRaw.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self))
                                let value = Double(bitPattern: bits)
                                guard value.isFinite else { return nil }
                                coefficients[index] = value
                            }
                            return body(0, x) { coefficients[$0] }
                        }
                    }
                }
            }
        }

        private func withRawBytes<Result>(_ body: (UnsafeRawBufferPointer) -> Result) -> Result {
            if let mappedData { return mappedData.withUnsafeBytes(body) }
            return data.withUnsafeBytes(body)
        }

        private func evaluate(
            record: Int, x: Double, coefficient: (Int) -> Double
        ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
            var position = SIMD3<Double>()
            var velocity = SIMD3<Double>()
            for axis in 0..<3 {
                let base = (record * 3 + axis) * coefficientCount
                var (b1, b2, d1, d2) = (0.0, 0.0, 0.0, 0.0)
                for k in stride(from: coefficientCount - 1, to: 0, by: -1) {
                    let b = 2 * x * b1 - b2 + coefficient(base + k)
                    let d = 2 * b1 + 2 * x * d1 - d2
                    (b2, b1) = (b1, b)
                    (d2, d1) = (d1, d)
                }
                position[axis] = coefficient(base) + x * b1 - b2
                velocity[axis] = (b1 + x * d1 - d2) * 2 / days
            }
            return (position, velocity)
        }

        private func acceleration(record: Int, x: Double, coefficient: (Int) -> Double) -> SIMD3<Double> {
            evaluateAndAcceleration(record: record, x: x, coefficient: coefficient).acceleration
        }

        private func evaluateAndAcceleration(
            record: Int, x: Double, coefficient: (Int) -> Double
        ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>, acceleration: SIMD3<Double>) {
            var position = SIMD3<Double>()
            var velocity = SIMD3<Double>()
            var result = SIMD3<Double>()
            for axis in 0..<3 {
                let base = (record * 3 + axis) * coefficientCount
                var (b1, b2, d1, d2, a1, a2) = (0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
                for k in stride(from: coefficientCount - 1, to: 0, by: -1) {
                    let b = 2 * x * b1 - b2 + coefficient(base + k)
                    let d = 2 * b1 + 2 * x * d1 - d2
                    let a = 4 * d1 + 2 * x * a1 - a2
                    (b2, b1) = (b1, b)
                    (d2, d1) = (d1, d)
                    (a2, a1) = (a1, a)
                }
                position[axis] = coefficient(base) + x * b1 - b2
                velocity[axis] = (b1 + x * d1 - d2) * 2 / days
                result[axis] = (2 * d1 + x * a1 - a2) * 4 / (days * days)
            }
            return (position, velocity, result)
        }
    }
}

import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

extension Engine {
    struct TableResource: Sendable {
        let name: String
        let byteCount: Int
        let sha256: String
    }

    final class MappedBytes: @unchecked Sendable {
        enum MappingError: Error, Equatable {
            case cannotOpen
            case cannotInspect
            case byteCount(expected: Int, actual: Int)
            case cannotMap
            case checksum(expected: String, actual: String)
        }

        let count: Int
        private let address: UnsafeRawPointer

        init(url: URL, byteCount: Int, sha256: String) throws {
            let descriptor = url.withUnsafeFileSystemRepresentation { path in
                path.map { open($0, O_RDONLY | O_CLOEXEC) } ?? -1
            }
            guard descriptor >= 0 else { throw MappingError.cannotOpen }
            defer { close(descriptor) }
            var status = stat()
            guard fstat(descriptor, &status) == 0 else { throw MappingError.cannotInspect }
            guard (status.st_mode & S_IFMT) == S_IFREG else { throw MappingError.cannotInspect }
            guard let actual = Int(exactly: status.st_size) else { throw MappingError.cannotInspect }
            guard actual == byteCount else { throw MappingError.byteCount(expected: byteCount, actual: actual) }
            guard actual > 0 else { throw MappingError.cannotMap }
            let mapped = mmap(nil, actual, PROT_READ, MAP_PRIVATE, descriptor, 0)
            guard mapped != MAP_FAILED, let mapped else { throw MappingError.cannotMap }
            let raw = UnsafeRawBufferPointer(start: mapped, count: actual)
            let actualDigest = Self.sha256(raw)
            guard actualDigest == sha256 else {
                munmap(mapped, actual)
                throw MappingError.checksum(expected: sha256, actual: actualDigest)
            }
            // Allow the OS to reclaim pages faulted during checksum verification
            // until records are actually read.
            _ = madvise(mapped, actual, MADV_DONTNEED)
            count = actual
            address = UnsafeRawPointer(mapped)
        }

        deinit {
            munmap(UnsafeMutableRawPointer(mutating: address), count)
        }

        static func bundled(_ resource: TableResource) -> MappedBytes {
            guard
                let url = Bundle.module.url(
                    forResource: resource.name, withExtension: "bin", subdirectory: "ModelTables")
            else {
                preconditionFailure("Missing bundled model table: \(resource.name).bin")
            }
            do {
                return try MappedBytes(url: url, byteCount: resource.byteCount, sha256: resource.sha256)
            } catch {
                preconditionFailure("Invalid bundled model table \(resource.name).bin: \(error)")
            }
        }

        func withUnsafeBytes<Result>(_ body: (UnsafeRawBufferPointer) throws -> Result) rethrows -> Result {
            try withExtendedLifetime(self) {
                try body(UnsafeRawBufferPointer(start: address, count: count))
            }
        }

        func littleEndianUInt64(at offset: Int) -> UInt64? {
            guard offset >= 0, offset <= count - 8 else { return nil }
            return withUnsafeBytes { UInt64(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt64.self)) }
        }

        private static let hexDigits: [UInt8] = Array("0123456789abcdef".utf8)

        private static func hexString<Bytes: Sequence>(of bytes: Bytes) -> String where Bytes.Element == UInt8 {
            var utf8: [UInt8] = []
            utf8.reserveCapacity(64)
            for byte in bytes {
                utf8.append(hexDigits[Int(byte >> 4)])
                utf8.append(hexDigits[Int(byte & 0x0f)])
            }
            return String(decoding: utf8, as: UTF8.self)
        }

        private static func sha256(_ bytes: UnsafeRawBufferPointer) -> String {
            #if canImport(CryptoKit)
            var hasher = CryptoKit.SHA256()
            hasher.update(bufferPointer: bytes)
            return hexString(of: hasher.finalize())
            #else
            return pureSwiftSHA256(bytes)
            #endif
        }

        #if !canImport(CryptoKit)
        private static let sha256Constants: [UInt32] = [
            0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4,
            0xab1c_5ed5, 0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe,
            0x9bdc_06a7, 0xc19b_f174, 0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f,
            0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da, 0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7,
            0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967, 0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc,
            0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85, 0xa2bf_e8a1, 0xa81a_664b,
            0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070, 0x19a4_c116,
            0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
            0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7,
            0xc671_78f2,
        ]

        private static func pureSwiftSHA256(_ bytes: UnsafeRawBufferPointer) -> String {
            var h0: UInt32 = 0x6a09_e667
            var h1: UInt32 = 0xbb67_ae85
            var h2: UInt32 = 0x3c6e_f372
            var h3: UInt32 = 0xa54f_f53a
            var h4: UInt32 = 0x510e_527f
            var h5: UInt32 = 0x9b05_688c
            var h6: UInt32 = 0x1f83_d9ab
            var h7: UInt32 = 0x5be0_cd19

            let totalBytes = bytes.count
            let bitCount = UInt64(totalBytes) &* 8
            let fullBlocksEnd = (totalBytes / 64) * 64

            withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { words in
                sha256Constants.withUnsafeBufferPointer { constants in
                    @inline(__always)
                    func compress() {
                        for index in 16..<64 {
                            let x = words[index - 15]
                            let y = words[index - 2]
                            let s0 = x.rotateRight(7) ^ x.rotateRight(18) ^ (x >> 3)
                            let s1 = y.rotateRight(17) ^ y.rotateRight(19) ^ (y >> 10)
                            words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
                        }
                        var (a, b, c, d, e, f, g, h) = (h0, h1, h2, h3, h4, h5, h6, h7)
                        for index in 0..<64 {
                            let s1 = e.rotateRight(6) ^ e.rotateRight(11) ^ e.rotateRight(25)
                            let choose = (e & f) ^ (~e & g)
                            let t1 = h &+ s1 &+ choose &+ constants[index] &+ words[index]
                            let s0 = a.rotateRight(2) ^ a.rotateRight(13) ^ a.rotateRight(22)
                            let majority = (a & b) ^ (a & c) ^ (b & c)
                            let t2 = s0 &+ majority
                            h = g
                            g = f
                            f = e
                            e = d &+ t1
                            d = c
                            c = b
                            b = a
                            a = t1 &+ t2
                        }
                        h0 &+= a
                        h1 &+= b
                        h2 &+= c
                        h3 &+= d
                        h4 &+= e
                        h5 &+= f
                        h6 &+= g
                        h7 &+= h
                    }

                    for blockStart in stride(from: 0, to: fullBlocksEnd, by: 64) {
                        for index in 0..<16 {
                            words[index] = UInt32(
                                bigEndian: bytes.loadUnaligned(fromByteOffset: blockStart + index * 4, as: UInt32.self))
                        }
                        compress()
                    }

                    withUnsafeTemporaryAllocation(of: UInt8.self, capacity: 128) { tail in
                        tail.initialize(repeating: 0)
                        defer { tail.deinitialize() }
                        let remainder = totalBytes - fullBlocksEnd
                        for index in 0..<remainder {
                            tail[index] = bytes[fullBlocksEnd + index]
                        }
                        tail[remainder] = 0x80
                        let tailBlocks = remainder + 9 <= 64 ? 64 : 128
                        for shiftIndex in 0..<8 {
                            tail[tailBlocks - 1 - shiftIndex] = UInt8(
                                truncatingIfNeeded: bitCount >> UInt64(shiftIndex * 8))
                        }
                        let tailRaw = UnsafeRawBufferPointer(tail)
                        for blockStart in stride(from: 0, to: tailBlocks, by: 64) {
                            for index in 0..<16 {
                                words[index] = UInt32(
                                    bigEndian: tailRaw.loadUnaligned(
                                        fromByteOffset: blockStart + index * 4, as: UInt32.self))
                            }
                            compress()
                        }
                    }
                }
            }

            var digestBytes: [UInt8] = []
            digestBytes.reserveCapacity(32)
            for word in [h0, h1, h2, h3, h4, h5, h6, h7] {
                digestBytes.append(UInt8(truncatingIfNeeded: word >> 24))
                digestBytes.append(UInt8(truncatingIfNeeded: word >> 16))
                digestBytes.append(UInt8(truncatingIfNeeded: word >> 8))
                digestBytes.append(UInt8(truncatingIfNeeded: word))
            }
            return hexString(of: digestBytes)
        }
        #endif
    }

    final class MappedResourceCache: Engine.ResettableCache, @unchecked Sendable {
        private let resources: [TableResource]
        private let lock = NSLock()
        private var mapped: [Int: MappedBytes] = [:]

        init(_ resources: [TableResource], registry: Engine.CacheRegistry = .shared) {
            self.resources = resources
            registry.register(self)
        }

        func resource(at index: Int) -> MappedBytes {
            precondition(resources.indices.contains(index), "Mapped resource index is out of bounds")
            if let value = lock.withLock({ mapped[index] }) { return value }
            // Map and verify outside the lock so other threads can read cached chunks concurrently.
            let loaded = MappedBytes.bundled(resources[index])
            return lock.withLock {
                if let existing = mapped[index] { return existing }
                mapped[index] = loaded
                return loaded
            }
        }

        func removeAll() {
            lock.withLock { mapped.removeAll() }
        }
    }

    struct Binary64Table: RandomAccessCollection, Sendable {
        typealias Index = Int
        private let values: [Double]?
        private let mapped: MappedBytes?
        let count: Int

        init(_ values: [Double]) {
            self.values = values
            mapped = nil
            count = values.count
        }

        init(resource: TableResource) {
            precondition(resource.byteCount % 8 == 0, "A binary64 resource has a partial value")
            values = nil
            mapped = MappedBytes.bundled(resource)
            count = resource.byteCount / 8
        }

        var startIndex: Int { 0 }
        var endIndex: Int { count }

        subscript(index: Int) -> Double {
            precondition(indices.contains(index), "Binary64 table index is out of bounds")
            if let values { return values[index] }
            guard let bits = mapped?.littleEndianUInt64(at: index * 8) else {
                preconditionFailure("Binary64 resource access is out of bounds")
            }
            return Double(bitPattern: bits)
        }

        func withElementAccessor<Result>(_ body: ((Int) -> Double) throws -> Result) rethrows -> Result {
            if let values {
                return try values.withUnsafeBufferPointer { buffer in
                    try body { buffer[$0] }
                }
            }
            guard let mapped else { preconditionFailure("Binary64 table has no backing storage") }
            return try mapped.withUnsafeBytes { raw in
                try body { index in
                    Double(
                        bitPattern: UInt64(
                            littleEndian: raw.loadUnaligned(fromByteOffset: index * 8, as: UInt64.self)))
                }
            }
        }
    }
}

#if !canImport(CryptoKit)
extension UInt32 {
    fileprivate func rotateRight(_ count: UInt32) -> UInt32 {
        self >> count | self << (32 - count)
    }
}
#endif

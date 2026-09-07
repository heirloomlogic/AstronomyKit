import CLibAstronomy
import Dispatch
import Testing

/// Regression coverage for the bounded, thread-local cache used by the pure
/// VSOP position, derivative, and radius series.
@Suite("VSOP Cache")
struct VsopCacheTests {
    private struct TripleBits: Equatable, Sendable {
        let x: UInt64
        let y: UInt64
        let z: UInt64
    }

    private struct StateBits: Equatable, Sendable {
        let position: TripleBits
        let velocity: TripleBits
    }

    private struct ResultBits: Equatable, Sendable {
        let vector: TripleBits
        let state: StateBits
        let radius: UInt64
    }

    private struct Query: Sendable {
        let bodyIndex: Int
        let tt: Double
    }

    private static func body(at index: Int) -> astro_body_t {
        switch index {
        case 0: BODY_MERCURY
        case 1: BODY_VENUS
        case 2: BODY_EARTH
        case 3: BODY_MARS
        case 4: BODY_JUPITER
        case 5: BODY_SATURN
        case 6: BODY_URANUS
        case 7: BODY_NEPTUNE
        default: BODY_INVALID
        }
    }

    private static func rawTime(
        tt: Double,
        metadataSeed: Double
    ) -> astro_time_t {
        astro_time_t(
            ut: metadataSeed,
            tt: tt,
            psi: metadataSeed + 0.125,
            eps: metadataSeed - 0.25,
            st: -metadataSeed
        )
    }

    private static func bits(_ value: Double) -> UInt64 {
        value.bitPattern
    }

    private static func bits(_ time: astro_time_t) -> [UInt64] {
        [bits(time.ut), bits(time.tt), bits(time.psi), bits(time.eps), bits(time.st)]
    }

    private static func vectorBits(
        body: astro_body_t,
        time: astro_time_t
    ) -> TripleBits {
        let result = Astronomy_HelioVector(body, time)
        #expect(result.status == ASTRO_SUCCESS)
        #expect(bits(result.t) == bits(time), "HelioVector must return the caller's complete time")
        return TripleBits(x: bits(result.x), y: bits(result.y), z: bits(result.z))
    }

    private static func stateBits(
        body: astro_body_t,
        time: astro_time_t
    ) -> StateBits {
        let result = Astronomy_HelioState(body, time)
        #expect(result.status == ASTRO_SUCCESS)
        #expect(bits(result.t) == bits(time), "HelioState must return the caller's complete time")
        return StateBits(
            position: TripleBits(x: bits(result.x), y: bits(result.y), z: bits(result.z)),
            velocity: TripleBits(x: bits(result.vx), y: bits(result.vy), z: bits(result.vz))
        )
    }

    private static func radiusBits(
        body: astro_body_t,
        time: astro_time_t
    ) -> UInt64 {
        let result = Astronomy_HelioDistance(body, time)
        #expect(result.status == ASTRO_SUCCESS)
        return bits(result.value)
    }

    private static func capture(
        body: astro_body_t,
        time: astro_time_t,
        order: Int = 0
    ) -> ResultBits {
        switch order % 3 {
        case 0:
            return ResultBits(
                vector: vectorBits(body: body, time: time),
                state: stateBits(body: body, time: time),
                radius: radiusBits(body: body, time: time)
            )
        case 1:
            let radius = radiusBits(body: body, time: time)
            let vector = vectorBits(body: body, time: time)
            let state = stateBits(body: body, time: time)
            return ResultBits(vector: vector, state: state, radius: radius)
        default:
            let state = stateBits(body: body, time: time)
            let radius = radiusBits(body: body, time: time)
            let vector = vectorBits(body: body, time: time)
            return ResultBits(vector: vector, state: state, radius: radius)
        }
    }

    @Test("Exact TT keys preserve caller time metadata")
    func sameTTDifferentMetadata() {
        let body = Self.body(at: 3)
        let firstTime = Self.rawTime(tt: 0.0, metadataSeed: 12_345.5)
        let secondTime = Self.rawTime(tt: 0.0, metadataSeed: -98_765.25)
        let thirdTime = Self.rawTime(tt: 0.0, metadataSeed: 0.03125)

        let first = Self.capture(body: body, time: firstTime, order: 0)
        let second = Self.capture(body: body, time: secondTime, order: 1)
        let third = Self.capture(body: body, time: thirdTime, order: 2)

        #expect(first == second)
        #expect(second == third)
    }

    @Test("Raw negative and signed-zero TT values remain exact")
    func rawNegativeAndSignedZeroTT() {
        let body = Self.body(at: 0)
        let negative = Self.capture(
            body: body,
            time: Self.rawTime(tt: -12_345.678_901_234_5, metadataSeed: 1.0)
        )
        let negativeAgain = Self.capture(
            body: body,
            time: Self.rawTime(tt: -12_345.678_901_234_5, metadataSeed: 2.0),
            order: 2
        )
        #expect(negative == negativeAgain)

        let positiveZero = Self.capture(
            body: body,
            time: Self.rawTime(tt: 0.0, metadataSeed: 3.0)
        )
        let negativeZero = Self.capture(
            body: body,
            time: Self.rawTime(tt: -0.0, metadataSeed: 4.0),
            order: 1
        )
        #expect(positiveZero == negativeZero)
    }

    @Test("Body and epoch keys survive replay and eviction")
    func bodyAndEpochIsolation() {
        let commonTime = Self.rawTime(tt: -43_210.25, metadataSeed: 10.0)
        let bodyReferences = (0..<8).map { bodyIndex in
            Self.capture(body: Self.body(at: bodyIndex), time: commonTime, order: bodyIndex)
        }

        for left in 0..<bodyReferences.count {
            for right in (left + 1)..<bodyReferences.count {
                #expect(
                    bodyReferences[left] != bodyReferences[right],
                    "Distinct VSOP models must not alias one cache entry"
                )
            }
        }

        let bodyReplayOrder = [3, 0, 7, 1, 6, 2, 5, 4]
        for round in 0..<4 {
            for bodyIndex in bodyReplayOrder {
                let actual = Self.capture(
                    body: Self.body(at: bodyIndex),
                    time: Self.rawTime(
                        tt: commonTime.tt,
                        metadataSeed: Double(100 * round + bodyIndex)
                    ),
                    order: round + bodyIndex
                )
                #expect(actual == bodyReferences[bodyIndex])
            }
        }

        // Sixty-five epochs force more than two turnovers of the 32-entry body cache.
        let epochs = (0..<65).map { -80_000.0 + Double($0) * 257.125 }
        let epochReferences = epochs.enumerated().map { index, tt in
            Self.capture(
                body: Self.body(at: 5),
                time: Self.rawTime(tt: tt, metadataSeed: Double(index)),
                order: index
            )
        }
        #expect(epochReferences.first != epochReferences.last)

        for index in epochs.indices.reversed() {
            let actual = Self.capture(
                body: Self.body(at: 5),
                time: Self.rawTime(tt: epochs[index], metadataSeed: Double(index + 1_000)),
                order: index + 1
            )
            #expect(actual == epochReferences[index])
        }
    }

    @Test("Concurrent threads match serial references in different call orders")
    func concurrentThreadsMatchSerialReferences() {
        let epochs = [-365_250.0, -20_000.125, -0.0, 0.0, 52_000.75]
        let queries = (0..<8).flatMap { bodyIndex in
            epochs.map { Query(bodyIndex: bodyIndex, tt: $0) }
        }
        let references = queries.enumerated().map { index, query in
            Self.capture(
                body: Self.body(at: query.bodyIndex),
                time: Self.rawTime(tt: query.tt, metadataSeed: Double(index)),
                order: index
            )
        }

        DispatchQueue.concurrentPerform(iterations: 12) { worker in
            for pass in 0..<3 {
                for offset in queries.indices {
                    let index = (offset * 17 + worker * 11 + pass * 7) % queries.count
                    let query = queries[index]
                    let actual = Self.capture(
                        body: Self.body(at: query.bodyIndex),
                        time: Self.rawTime(
                            tt: query.tt,
                            metadataSeed: Double(10_000 * worker + 100 * pass + offset)
                        ),
                        order: worker + pass + offset
                    )
                    #expect(actual == references[index])
                }
            }
        }
    }
}

import CLibAstronomy
import Dispatch
import Testing

@Suite("Nutation Cache")
struct NutationCacheTests {
    private struct NutationBits: Equatable, Sendable {
        let psi: UInt64
        let eps: UInt64
        let psiRate: UInt64
        let epsRate: UInt64
    }

    private static let representativeEpochs = [-40_000.25, -0.0, 0.0, 12_345.625, 40_000.75]

    private static func rawTime(
        tt: Double,
        metadataSeed: Double,
        psi: Double = .nan,
        eps: Double = .nan
    ) -> astro_time_t {
        astro_time_t(
            ut: metadataSeed,
            tt: tt,
            psi: psi,
            eps: eps,
            st: -metadataSeed
        )
    }

    private static func evaluate(tt: Double, metadataSeed: Double = 0) -> (astro_time_t, NutationBits) {
        var time = rawTime(tt: tt, metadataSeed: metadataSeed)
        var psiRate = 0.0
        var epsRate = 0.0
        _Astronomy_Iau2000bRates(&time, &psiRate, &epsRate)
        return (
            time,
            NutationBits(
                psi: time.psi.bitPattern,
                eps: time.eps.bitPattern,
                psiRate: psiRate.bitPattern,
                epsRate: epsRate.bitPattern
            )
        )
    }

    @Test("Cached angles and rates replay exact bits")
    func exactBits() {
        for tt in Self.representativeEpochs {
            let first = Self.evaluate(tt: tt, metadataSeed: 17)
            let second = Self.evaluate(tt: tt, metadataSeed: -91)
            #expect(second.1 == first.1, "warm result at tt \(tt)")
            #expect(first.0.ut.bitPattern == 17.0.bitPattern)
            #expect(first.0.tt.bitPattern == tt.bitPattern)
            #expect(first.0.st.bitPattern == (-17.0).bitPattern)
            #expect(second.0.ut.bitPattern == (-91.0).bitPattern)
            #expect(second.0.tt.bitPattern == tt.bitPattern)
            #expect(second.0.st.bitPattern == 91.0.bitPattern)
        }
    }

    @Test("A caller's populated angle memo remains authoritative")
    func populatedTimeMemo() {
        let tt = 7_654.125
        let reference = Self.evaluate(tt: tt).1
        var time = Self.rawTime(tt: tt, metadataSeed: 12, psi: -1.25, eps: 2.5)
        var psiRate = 0.0
        var epsRate = 0.0
        _Astronomy_Iau2000bRates(&time, &psiRate, &epsRate)

        #expect(time.psi.bitPattern == (-1.25).bitPattern)
        #expect(time.eps.bitPattern == 2.5.bitPattern)
        #expect(psiRate.bitPattern == reference.psiRate)
        #expect(epsRate.bitPattern == reference.epsRate)
    }

    @Test("Caller metadata survives state calculation")
    func stateMetadata() {
        let original = Self.rawTime(tt: -24_680.5, metadataSeed: 1_234.75)
        let state = Astronomy_GeoEclipticState(BODY_MARS, original, ABERRATION)
        #expect(state.status == ASTRO_SUCCESS)
        #expect(state.t.ut.bitPattern == original.ut.bitPattern)
        #expect(state.t.tt.bitPattern == original.tt.bitPattern)
        #expect(state.t.psi.bitPattern == original.psi.bitPattern)
        #expect(state.t.eps.bitPattern == original.eps.bitPattern)
        #expect(state.t.st.bitPattern == original.st.bitPattern)
    }

    @Test("Nonfinite epochs preserve uncached evaluation behavior")
    func nonfinite() {
        for tt in [Double.infinity, -Double.infinity, Double.nan] {
            let (time, result) = Self.evaluate(tt: tt)
            #expect(time.psi.isNaN)
            #expect(time.eps.isNaN)
            #expect(Double(bitPattern: result.psiRate).isNaN)
            #expect(Double(bitPattern: result.epsRate).isNaN)
        }
    }

    @Test("Concurrent threads match serial references")
    func concurrentThreads() {
        let epochs = Self.representativeEpochs
        let references = epochs.map { Self.evaluate(tt: $0).1 }
        DispatchQueue.concurrentPerform(iterations: 12) { worker in
            for pass in 0..<20 {
                let index = (worker * 7 + pass * 3) % epochs.count
                let actual = Self.evaluate(
                    tt: epochs[index],
                    metadataSeed: Double(worker * 100 + pass)
                ).1
                #expect(actual == references[index])
            }
        }
    }
}

import CLibAstronomy
import Dispatch
import Testing

@testable import AstronomyKit

@Suite("Moon Cache")
struct MoonCacheTests {
    private struct StateBits: Equatable, Sendable {
        let position: [UInt64]
        let rates: [UInt64]
    }

    private static let representativeEpochs = [-40_000.25, -0.0, 0.0, 12_345.625, 40_000.75]

    private static func stateBits(tt: Double) throws -> StateBits {
        let state = try Moon.eclipticState(at: AstroTime(tt: tt))
        return StateBits(
            position: [
                state.longitude.bitPattern,
                state.latitude.bitPattern,
                state.distance.bitPattern,
            ],
            rates: [
                state.longitudeRate.bitPattern,
                state.latitudeRate.bitPattern,
                state.distanceRate.bitPattern,
            ]
        )
    }

    @Test("Repeated states replay identical position and rate bits")
    func repeatedStates() throws {
        for tt in Self.representativeEpochs {
            let reference = try Self.stateBits(tt: tt)
            for _ in 0..<12 {
                #expect(try Self.stateBits(tt: tt) == reference)
            }
        }
    }

    @Test("Position, state, and libration clients share stable results")
    func clientsRemainStable() throws {
        for tt in Self.representativeEpochs {
            let time = AstroTime(tt: tt)
            let ecliptic = try Moon.ecliptic(at: time)
            let state = try Moon.eclipticState(at: time)
            let libration = Moon.libration(at: time)
            let repeatedLibration = Moon.libration(at: time)

            #expect(state.longitude.bitPattern == ecliptic.longitude.bitPattern)
            #expect(state.latitude.bitPattern == ecliptic.latitude.bitPattern)
            #expect(state.distance.bitPattern == ecliptic.distance.bitPattern)
            #expect(libration.moonLongitude.bitPattern == repeatedLibration.moonLongitude.bitPattern)
            #expect(libration.moonLatitude.bitPattern == repeatedLibration.moonLatitude.bitPattern)
            #expect(libration.distanceKM.bitPattern == repeatedLibration.distanceKM.bitPattern)
        }
    }

    @Test("Nonfinite TT keeps propagating nonfinite lunar output")
    func nonfinite() {
        for tt in [Double.infinity, -Double.infinity, Double.nan] {
            let time = astro_time_t(ut: tt, tt: tt, psi: .nan, eps: .nan, st: .nan)
            let vector = Astronomy_GeoMoon(time)
            let sphere = Astronomy_EclipticGeoMoon(time)
            #expect(!vector.x.isFinite)
            #expect(!vector.y.isFinite)
            #expect(!vector.z.isFinite)
            #expect(!sphere.lat.isFinite)
            #expect(!sphere.dist.isFinite)
        }
    }

    @Test("Concurrent threads match serial references")
    func concurrentThreads() throws {
        let epochs = Self.representativeEpochs
        let references = try epochs.map(Self.stateBits)
        DispatchQueue.concurrentPerform(iterations: 12) { worker in
            for pass in 0..<20 {
                let index = (worker * 7 + pass * 3) % epochs.count
                do {
                    #expect(try Self.stateBits(tt: epochs[index]) == references[index])
                } catch {
                    Issue.record(error)
                }
            }
        }
    }
}

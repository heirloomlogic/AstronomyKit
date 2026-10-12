import Foundation
import Testing

@testable import AstronomyKit

@Suite("Complete DE441 Moon integration")
struct EngineMoonFullIntegrationTests {
    @Test("Adjacent TT instants that collapse in centuries retain separate cached source states")
    func exactClockCache() throws {
        let first = -1_000_000.25
        let second = first.nextUp
        #expect(first != second && first / 36_525 == second / 36_525)
        #expect(first / 36_525 * 36_525 != first)
        let (cache, _) = EngineMoonCacheTests.makeCache()
        let a = Engine.Moon.coordinates(tt: first, cache: cache)
        let b = Engine.Moon.coordinates(tt: second, cache: cache)
        #expect(a != b)
        #expect(cache.statistics == EngineMoonCacheTests.Statistics(hits: 0, misses: 2))
        #expect(Engine.Moon.coordinates(tt: first, cache: cache) == a)
        #expect(cache.statistics == EngineMoonCacheTests.Statistics(hits: 1, misses: 2))
        for tt in [first, second] {
            let direct = try #require(Engine.MoonDE441Full.state(tt: tt))
            let cached = try Engine.Moon.geocentricState(at: PlanetTestSupport.time(tt: tt), cache: cache)
            #expect(EngineMoonEphemerisTests.largest(SIMD3(cached.x, cached.y, cached.z) - direct.position) < 1e-17)
        }
    }

    @Test("Public geometric Moon states retain the complete outer source")
    func publicSource() throws {
        for tt in [-1_461_000.0, -1_000_000.25, -200_000.5, 200_000.25, 1_000_000.75, 1_461_000] {
            let source = try #require(Engine.MoonDE441Full.state(tt: tt))
            let time = AstroTime(tt: tt)
            let position = try Moon.geocentricPosition(at: time)
            let state = try Moon.geoState(at: time)
            let actual = SIMD3(position.x, position.y, position.z)
            #expect(EngineMoonEphemerisTests.largest(actual - source.position) < 1e-16)
            #expect([state.position.x, state.position.y, state.position.z] == [position.x, position.y, position.z])
            let native = try Engine.Moon.geocentricState(at: PlanetTestSupport.time(tt: tt))
            #expect(EngineMoonEphemerisTests.largest(SIMD3(native.vx, native.vy, native.vz) - source.velocity) < 1e-16)
        }
    }

    @Test("Private apparent emission padding uses the same complete lunar source")
    func emissionPadding() throws {
        for tt in [-Engine.acceptedTTDays - 2, -Engine.acceptedTTDays - 0.125] {
            let source = try #require(Engine.MoonDE441Full.state(tt: tt))
            let moon = try Engine.ApparentPlace.bodyMotion(.moon, tt: tt)
            let earth = try Engine.ApparentPlace.bodyMotion(.earth, tt: tt)
            #expect(EngineMoonEphemerisTests.largest(moon.value - earth.value - source.position) < 1e-15)
            #expect(EngineMoonEphemerisTests.largest(moon.rate - earth.rate - source.velocity) < 1e-16)
        }
    }

    @Test("Public routing preserves the selected source at chunk seams and adjacent TT instants")
    func selectedSeams() throws {
        typealias Table = Engine.MoonDE441Full
        let records =
            Array(stride(from: Table.recordsPerChunk, to: Table.recordCount, by: Table.recordsPerChunk))
            + [1, 362_473, Table.recordCount - 1]
        for record in records {
            let tdb = Table.start + Double(record) * 4
            let tt = tdb - Engine.TDB.offsetSeconds(tt: tdb) / Engine.secondsPerDay
            for instant in [tt.nextDown, tt, tt.nextUp] {
                guard abs(instant) <= Engine.acceptedTTDays,
                    Engine.MoonEphemeris.weight(tt: instant).weight == 0
                else { continue }
                let source = try #require(Table.state(tt: instant))
                let state = try Moon.geoState(at: AstroTime(tt: instant))
                let p = SIMD3(state.position.x, state.position.y, state.position.z)
                #expect(EngineMoonEphemerisTests.largest(p - source.position) < 1e-17)
                let native = try Engine.Moon.geocentricState(at: PlanetTestSupport.time(tt: instant))
                #expect(
                    EngineMoonEphemerisTests.largest(SIMD3(native.vx, native.vy, native.vz) - source.velocity) < 1e-16)
            }
        }
    }

    @Test("Moon consumers accept both public endpoints and reject exterior reception times")
    func publicDomain() throws {
        let observer = Observer(latitude: 38, longitude: -77, height: 100)
        for tt in [-Engine.acceptedTTDays, Engine.acceptedTTDays] {
            let time = AstroTime(tt: tt)
            _ = try Moon.ecliptic(at: time)
            _ = try Moon.eclipticState(at: time)
            _ = try CelestialBody.earthMoonBaryState(at: time)
            _ = try CelestialBody.moon.heliocentricState(at: time)
            _ = try CelestialBody.moon.barycentricState(at: time)
            _ = try CelestialBody.moon.angleFromSun(at: time)
            for mode in [Aberration.none, .corrected] {
                let position = try CelestialBody.moon.geocentricPosition(at: time, aberration: mode)
                #expect(position.x.isFinite && position.y.isFinite && position.z.isFinite)
                _ = try CelestialBody.moon.geocentricEclipticState(at: time, aberration: mode)
                _ = try CelestialBody.moon.equatorial(at: time, from: observer, aberration: mode)
                _ = try CelestialBody.moon.backdatedPosition(at: time, seenFrom: .earth, aberration: mode)
            }
        }
        for tt in [(-Engine.acceptedTTDays).nextDown, Engine.acceptedTTDays.nextUp, .nan, .infinity] {
            let time = AstroTime(tt: tt)
            #expect(throws: AstronomyError.badTime) { try Moon.geoState(at: time) }
            for mode in [Aberration.none, .corrected] {
                #expect(throws: AstronomyError.badTime) {
                    try CelestialBody.moon.geocentricPosition(at: time, aberration: mode)
                }
                #expect(throws: AstronomyError.badTime) {
                    try CelestialBody.moon.geocentricEclipticState(at: time, aberration: mode)
                }
                #expect(throws: AstronomyError.badTime) {
                    try CelestialBody.moon.equatorial(at: time, from: observer, aberration: mode)
                }
            }
        }
    }
}

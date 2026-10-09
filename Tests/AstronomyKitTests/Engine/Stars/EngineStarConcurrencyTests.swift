import Testing

@testable import AstronomyKit

@Suite("Native fixed-star concurrency")
struct EngineStarConcurrencyTests {
    private struct Snapshot: Equatable, Sendable {
        let values: [Double]
        let constellation: String
    }

    @Test("Distinct immutable stars remain repeatable during process model updates")
    func distinctStarsAndModelUpdates() async throws {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }
        let observer = Observer(latitude: 35.595, longitude: -82.5572, height: 812)
        let stars = (0..<24).map { index in
            Engine.Star(
                rightAscension: Double(index) + 0.25,
                declination: -72 + 6 * Double(index),
                distance: 2 + Double(index) * 11
            )
        }
        let times = [
            Engine.Time(ut: 18_250, deltaTModel: .espenakMeeus),
            Engine.Time(ut: 18_250, deltaTModel: .jplHorizons),
        ]
        #expect(times[0].tt != times[1].tt)

        func snapshot(star: Engine.Star, time: Engine.Time) throws -> Snapshot {
            let position = try star.geocentricPosition(at: time, aberration: .corrected)
            let equatorial = try star.equatorial(at: time, from: observer, equatorDate: .ofDate)
            let ecliptic = try star.ecliptic(at: time)
            let horizontal = try star.horizontal(at: time, from: observer, refraction: .none)
            let constellation = try Engine.Constellations.find(
                rightAscension: star.rightAscension,
                declination: star.declination
            )
            return Snapshot(
                values: [
                    position.x, position.y, position.z,
                    equatorial.rightAscension, equatorial.declination, equatorial.distance,
                    ecliptic.longitude, ecliptic.latitude,
                    horizontal.azimuth, horizontal.altitude,
                ],
                constellation: constellation.symbol
            )
        }

        let references = try times.map { time in
            try stars.map { star in try snapshot(star: star, time: time) }
        }
        let modelCreations = EngineBoundedCacheTests.Counter()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for repetition in 0..<4 {
                for (timeIndex, time) in times.enumerated() {
                    group.addTask { () async throws -> Void in
                        for (starIndex, star) in stars.enumerated() {
                            #expect(try snapshot(star: star, time: time) == references[timeIndex][starIndex])
                            if (starIndex + repetition).isMultiple(of: 3) { await Task.yield() }
                        }
                    }
                }
            }
            for _ in 0..<2 {
                group.addTask {
                    for iteration in 0..<200 {
                        let model: DeltaTModel = iteration.isMultiple(of: 2) ? .espenakMeeus : .jplHorizons
                        AstronomyConfig.setDeltaTModel(model)
                        #expect(AstroTime(ut: 18_250).deltaTModel != nil)
                        modelCreations.record()
                        await Task.yield()
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(modelCreations.count == 400)
    }
}

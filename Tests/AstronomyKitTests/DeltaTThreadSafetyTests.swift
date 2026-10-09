import Foundation
import Testing

@testable import AstronomyKit

@Suite("Delta T Thread Safety")
struct DeltaTThreadSafetyTests {
    static func expectedTT(ut: Double, model: DeltaTModel) -> Double {
        let seconds =
            switch model {
            case .espenakMeeus: AstronomyConfig.deltaTEspenakMeeus(universalTime: ut)
            case .jplHorizons: AstronomyConfig.deltaTJplHorizons(universalTime: ut)
            }
        return ut + seconds / 86_400
    }

    @Test("An existing time keeps its public model when the process default changes")
    func calculationKeepsCapturedModel() throws {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }
        let observer = Observer(latitude: 40, longitude: 0)
        let ut = 18_250.0
        AstronomyConfig.setDeltaTModel(.jplHorizons)
        let captured = AstroTime(ut: ut)
        #expect(captured.deltaTModel == .jplHorizons)
        #expect(captured.terrestrialTime == Self.expectedTT(ut: ut, model: .jplHorizons))
        let before = try CelestialBody.sun.horizon(at: captured, from: observer, refraction: .none)

        AstronomyConfig.setDeltaTModel(.espenakMeeus)
        let current = AstroTime(ut: ut)
        #expect(current.deltaTModel == .espenakMeeus)
        #expect(current.terrestrialTime == Self.expectedTT(ut: ut, model: .espenakMeeus))
        #expect(current.terrestrialTime != captured.terrestrialTime)
        #expect(try CelestialBody.sun.horizon(at: captured, from: observer, refraction: .none) == before)
        let derived = captured.addingDays(10)
        #expect(derived.deltaTModel == .jplHorizons)
        #expect(derived.terrestrialTime == Self.expectedTT(ut: ut + 10, model: .jplHorizons))
    }

    @Test("Concurrent public model swaps publish complete models to time construction")
    func concurrentModelSwapIsSafe() async {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }
        let ut = 36_525.0
        let mismatches = EngineBoundedCacheTests.Counter()

        await withTaskGroup(of: Void.self) { group in
            for reader in 0..<8 {
                group.addTask {
                    for iteration in 0..<250 {
                        let time = AstroTime(ut: ut + Double((reader + iteration) % 3) / 8)
                        guard let model = time.deltaTModel else {
                            mismatches.record()
                            continue
                        }
                        if time.terrestrialTime != Self.expectedTT(ut: time.universalTime, model: model) {
                            mismatches.record()
                        }
                        if iteration.isMultiple(of: 5) { await Task.yield() }
                    }
                }
            }
            for writer in 0..<2 {
                group.addTask {
                    for iteration in 0..<500 {
                        let model: DeltaTModel =
                            (iteration + writer).isMultiple(of: 2) ? .espenakMeeus : .jplHorizons
                        AstronomyConfig.setDeltaTModel(model)
                        await Task.yield()
                    }
                }
            }
            await group.waitForAll()
        }

        #expect(mismatches.count == 0)
    }
}

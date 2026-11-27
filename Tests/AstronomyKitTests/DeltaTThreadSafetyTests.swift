import Testing

@testable import AstronomyKit

/// Verifies that distinct ``DeltaTModel`` values run concurrently with full isolation.
///
/// ``AstroTime`` carries its ``DeltaTModel`` by value with no process-global mutable
/// Delta T state, so tasks using `.observed`, `.espenakMeeus`, and `.jplHorizons`
/// simultaneously never interfere with one another.
@Suite("Delta T Concurrency Isolation")
struct DeltaTThreadSafetyTests {
    @Test("Concurrent multi-model AstroTime construction and searches stay isolated")
    func concurrentMultiModelIsolation() async throws {
        // Year 2027 (ut ≈ 9861.75): all three models produce distinct Delta T values.
        let ut = 27.0 * 365.25
        let observedDT = DeltaTModel.observed.deltaT(universalTime: ut)
        let espenakDT = DeltaTModel.espenakMeeus.deltaT(universalTime: ut)
        let jplDT = DeltaTModel.jplHorizons.deltaT(universalTime: ut)
        #expect(observedDT != espenakDT)
        #expect(observedDT != jplDT)
        #expect(espenakDT != jplDT)

        let expectedByModel: [DeltaTModel: Double] = [
            .observed: ut + observedDT / 86_400,
            .espenakMeeus: ut + espenakDT / 86_400,
            .jplHorizons: ut + jplDT / 86_400,
        ]

        let expectedSeasons: [DeltaTModel: Seasons] = [
            .observed: try Seasons.forYear(2_027, deltaT: .observed),
            .espenakMeeus: try Seasons.forYear(2_027, deltaT: .espenakMeeus),
            .jplHorizons: try Seasons.forYear(2_027, deltaT: .jplHorizons),
        ]

        try await withThrowingTaskGroup(of: Void.self) { group in
            for model in DeltaTModel.allCases {
                for _ in 0..<4 {
                    group.addTask {
                        let expectedTT = expectedByModel[model]!
                        let refSeasons = expectedSeasons[model]!
                        for _ in 0..<100 {
                            let t = AstroTime(ut: ut, deltaT: model)
                            #expect(t.deltaTModel == model)
                            #expect(t.terrestrialTime == expectedTT)

                            let shifted = t.addingDays(10)
                            #expect(shifted.deltaTModel == model)
                            #expect(
                                shifted.terrestrialTime
                                    == (ut + 10) + model.deltaT(universalTime: ut + 10) / 86_400
                            )

                            let ttShifted = t.addingTerrestrialDays(0.25)
                            #expect(ttShifted.deltaTModel == model)
                            #expect(ttShifted.terrestrialTime == expectedTT + 0.25)

                            let fromTT = AstroTime(tt: expectedTT, deltaT: model)
                            #expect(fromTT.deltaTModel == model)
                            #expect(abs(fromTT.universalTime - ut) < 1e-11)
                        }

                        let seasons = try Seasons.forYear(2_027, deltaT: model)
                        #expect(seasons == refSeasons)
                        #expect(seasons.marchEquinox.deltaTModel == model)
                        #expect(seasons.juneSolstice.deltaTModel == model)
                        #expect(seasons.septemberEquinox.deltaTModel == model)
                        #expect(seasons.decemberSolstice.deltaTModel == model)

                        let start = AstroTime(year: 2_027, month: 6, day: 1, deltaT: model)
                        let sunrise = try CelestialBody.sun.riseTime(
                            after: start,
                            from: .greenwich
                        )
                        #expect(sunrise?.deltaTModel == model)

                        let fullMoon = try Moon.searchPhase(.full, after: start)
                        #expect(fullMoon?.deltaTModel == model)

                        let eclipse = try Eclipse.searchGlobalSolar(after: start)
                        #expect(eclipse.peak.deltaTModel == model)
                    }
                }
            }
            try await group.waitForAll()
        }
    }
}

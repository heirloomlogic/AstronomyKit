import Synchronization
import Testing

@testable import AstronomyKit

/// Calls made through ``observedStandIn``.
private let standInCalls = Atomic<Int>(0)

/// A second Delta T function that returns the same bits as the observed model.
///
/// Swapping between this and the real observed function changes the
/// active model dispatch without changing any result, so suites running in
/// parallel cannot tell that a swap happened.
private let observedStandIn: @Sendable (Double) -> Double = { ut in
    standInCalls.add(1, ordering: .relaxed)
    return AstronomyConfig.deltaTObserved(universalTime: ut)
}

/// Verifies that the Delta T model can be swapped while calculations run on
/// other threads.
///
/// The engine stores the active Delta T model in an atomic selector that every
/// time construction reads; this suite exercises concurrent writers and readers
/// so ThreadSanitizer can prove the synchronization holds. Other suites construct
/// times in parallel, so the writers only swap in ``observedStandIn``; a model
/// with different results, such as JPL Horizons, would shift their answers.
@Suite("Delta T Thread Safety")
struct DeltaTThreadSafetyTests {
    @Test("Concurrent model swaps never corrupt time construction")
    func concurrentModelSwapIsSafe() async {
        defer { AstronomyConfig.setDeltaTModel(.observed) }

        // ~100 years after J2000, where Delta T is large and changing.
        let ut = 36_525.0
        let expectedTT = ut + AstronomyConfig.deltaTObserved(universalTime: ut) / 86_400

        await withTaskGroup(of: Void.self) { group in
            // Hammer time construction on several tasks...
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<200 {
                        // Whichever model wins the race, never a torn value.
                        #expect(AstroTime(ut: ut).terrestrialTime == expectedTT)
                    }
                }
            }

            // ...while other tasks repeatedly swap the Delta T function.
            for _ in 0..<2 {
                group.addTask {
                    for iteration in 0..<100 {
                        if iteration.isMultiple(of: 2) {
                            EngineTime.setCustomDeltaTFunction(observedStandIn)
                        } else {
                            AstronomyConfig.setDeltaTModel(.observed)
                        }
                        await Task.yield()
                    }
                }
            }

            await group.waitForAll()
        }

        // The swap only tests something if time construction reads the selector
        // the writers store. Install the stand-in once more and check it runs.
        EngineTime.setCustomDeltaTFunction(observedStandIn)
        let callsBefore = standInCalls.load(ordering: .relaxed)
        _ = AstroTime(ut: ut)
        #expect(standInCalls.load(ordering: .relaxed) > callsBefore)
    }
}

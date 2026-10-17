import AstronomyKit
import Foundation
import Testing

/// Verifies that the Delta T model can be swapped while calculations run on
/// other threads.
///
/// The underlying C library stores the active Delta T model in a global
/// function pointer that every time construction reads. A local patch makes
/// that pointer atomic; this suite exercises concurrent writers and readers
/// so ThreadSanitizer can prove the patch holds.
@Suite("Delta T Thread Safety", .serialized)
struct DeltaTThreadSafetyTests {
    /// A moment ~100 years after J2000, far enough out that every model
    /// gives a different Delta T.
    static let farFutureUT = 36_525.0

    @Test("Concurrent model swaps never corrupt time construction")
    func concurrentModelSwapIsSafe() async {
        defer { AstronomyConfig.setDeltaTModel(.iersObserved) }

        let ut = Self.farFutureUT
        let validTT: Set<Double> = [
            ut + AstronomyConfig.deltaTIersObserved(universalTime: ut) / 86_400,
            ut + AstronomyConfig.deltaTEspenakMeeus(universalTime: ut) / 86_400,
            ut + AstronomyConfig.deltaTJplHorizons(universalTime: ut) / 86_400,
        ]

        // The models must disagree here, or the test proves nothing.
        #expect(validTT.count == DeltaTModel.allCases.count)

        await withTaskGroup(of: Void.self) { group in
            // Hammer time construction on several tasks...
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<200 {
                        let tt = AstroTime(ut: ut).terrestrialTime
                        // Whichever model wins the race, the result must be
                        // one of the valid answers, never a torn value.
                        #expect(validTT.contains(tt))
                    }
                }
            }

            // ...while other tasks repeatedly swap the Delta T model.
            for _ in 0..<2 {
                group.addTask {
                    for iteration in 0..<100 {
                        AstronomyConfig.setDeltaTModel(
                            DeltaTModel.allCases[iteration % DeltaTModel.allCases.count]
                        )
                        await Task.yield()
                    }
                }
            }

            await group.waitForAll()
        }
    }
}

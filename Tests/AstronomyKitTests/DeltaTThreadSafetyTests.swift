import AstronomyKit
import CLibAstronomy
import Foundation
import Synchronization
import Testing

/// Calls made through ``espenakMeeusStandIn``.
private let standInCalls = Atomic<Int>(0)

/// A second Delta T function that returns the same bits as Espenak-Meeus.
///
/// Swapping between this and the real Espenak-Meeus function changes the
/// global function pointer without changing any result, so suites running in
/// parallel cannot tell that a swap happened.
private let espenakMeeusStandIn: astro_deltat_func = { ut in
    standInCalls.add(1, ordering: .relaxed)
    return Astronomy_DeltaT_EspenakMeeus(ut)
}

/// Calls made through ``selfReplacingStandIn``.
private let selfReplacingCalls = Atomic<Int>(0)

/// A Delta T function that returns the Espenak-Meeus bits and, on every call,
/// selects Espenak-Meeus as the process default. A calculation that keeps
/// calling it after its first derived time has kept its captured function.
private let selfReplacingStandIn: astro_deltat_func = { ut in
    selfReplacingCalls.add(1, ordering: .relaxed)
    AstronomyConfig.setDeltaTModel(.espenakMeeus)
    return Astronomy_DeltaT_EspenakMeeus(ut)
}

/// Verifies that the Delta T model can be swapped while calculations run on
/// other threads, and that a calculation in flight keeps the model its time
/// captured.
///
/// The underlying C library stores the active Delta T model in a global
/// function pointer that every time construction reads. A local patch makes
/// that pointer atomic; this suite exercises concurrent writers and readers
/// so ThreadSanitizer can prove the patch holds. Other suites construct times
/// in parallel, so the writers only swap in ``espenakMeeusStandIn``; a model
/// with different results, such as JPL Horizons, would shift their answers.
/// The suite is serialized because both tests install a stand-in and then
/// check which function a construction called.
@Suite("Delta T Thread Safety", .serialized)
struct DeltaTThreadSafetyTests {
    @Test("A calculation keeps its time's model when the default changes mid-calculation")
    func calculationKeepsCapturedModel() throws {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }
        let observer = Observer(latitude: 40, longitude: 0)

        // Constructing the time captures the stand-in; that first call also
        // puts Espenak-Meeus back as the default.
        let date = try #require(ISO8601DateFormatter().date(from: "2049-12-21T12:00:00Z"))
        Astronomy_SetDeltaTFunction(selfReplacingStandIn)
        let time = AstroTime(date)
        #expect(time.deltaTModel == nil)
        #expect(AstroTime(ut: 0).deltaTModel == .espenakMeeus)

        // The calculation's first derived time replaces the default again.
        // Every later derived time still calls the captured stand-in.
        Astronomy_SetDeltaTFunction(selfReplacingStandIn)
        let before = selfReplacingCalls.load(ordering: .relaxed)
        let horizon = try CelestialBody.sun.horizon(at: time, from: observer, refraction: .none)
        #expect(selfReplacingCalls.load(ordering: .relaxed) - before >= 2)
        #expect(AstroTime(ut: 0).deltaTModel == .espenakMeeus)

        // The stand-in returns the Espenak-Meeus bits, so the result is the
        // one a plain Espenak-Meeus time gives.
        let reference = try CelestialBody.sun.horizon(
            at: AstroTime(date, deltaTModel: .espenakMeeus),
            from: observer,
            refraction: .none
        )
        #expect(horizon == reference)
    }

    @Test("Concurrent model swaps never corrupt time construction")
    func concurrentModelSwapIsSafe() async {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }

        // ~100 years after J2000, where Delta T is large and changing.
        let ut = 36_525.0
        let expectedTT = ut + AstronomyConfig.deltaTEspenakMeeus(universalTime: ut) / 86_400

        await withTaskGroup(of: Void.self) { group in
            // Hammer time construction on several tasks...
            for _ in 0..<8 {
                group.addTask {
                    for _ in 0..<200 {
                        // Whichever pointer wins the race, never a torn value.
                        #expect(AstroTime(ut: ut).terrestrialTime == expectedTT)
                    }
                }
            }

            // ...while other tasks repeatedly swap the Delta T function.
            for _ in 0..<2 {
                group.addTask {
                    for iteration in 0..<100 {
                        if iteration.isMultiple(of: 2) {
                            Astronomy_SetDeltaTFunction(espenakMeeusStandIn)
                        } else {
                            AstronomyConfig.setDeltaTModel(.espenakMeeus)
                        }
                        await Task.yield()
                    }
                }
            }

            await group.waitForAll()
        }

        // The swap only tests something if time construction reads the pointer
        // the writers store. Install the stand-in once more and check it runs.
        Astronomy_SetDeltaTFunction(espenakMeeusStandIn)
        let callsBefore = standInCalls.load(ordering: .relaxed)
        _ = AstroTime(ut: ut)
        #expect(standInCalls.load(ordering: .relaxed) > callsBefore)
    }
}

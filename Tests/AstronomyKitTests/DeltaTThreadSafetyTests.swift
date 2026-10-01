import CLibAstronomy
import Foundation
import Synchronization
import Testing

@testable import AstronomyKit

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

/// Calls made through ``defaultChangingStandIn``.
private let defaultChangingCalls = Atomic<Int>(0)

/// A Delta T function that returns the Espenak-Meeus bits and, on every call,
/// installs ``espenakMeeusStandIn`` as the process default. A calculation that
/// calls it more than once kept using it after the default changed.
///
/// It is never installed as the default itself, so a time built by another
/// suite cannot capture it.
private let defaultChangingStandIn: astro_deltat_func = { ut in
    defaultChangingCalls.add(1, ordering: .relaxed)
    Astronomy_SetDeltaTFunction(espenakMeeusStandIn)
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
/// Other suites can also construct times or set the default between any two
/// statements here, so no assertion depends on which default is installed.
@Suite("Delta T Thread Safety")
struct DeltaTThreadSafetyTests {
    @Test("A calculation keeps its time's model when the default changes mid-calculation")
    func calculationKeepsCapturedModel() throws {
        defer { AstronomyConfig.setDeltaTModel(.espenakMeeus) }
        let observer = Observer(latitude: 40, longitude: 0)
        let date = try #require(ISO8601DateFormatter().date(from: "2049-12-21T12:00:00Z"))
        let reference = AstroTime(date, deltaTModel: .espenakMeeus)

        // Pass the stand-in to the time directly. Installing it as the default
        // first would let a time built by another suite capture it, or another
        // suite's default replace it, before this construction reads it.
        let time = AstroTime(
            raw: Astronomy_TimeFromPair(reference.universalTime, reference.terrestrialTime, defaultChangingStandIn)
        )
        #expect(time.deltaTModel == nil)

        // Each derived time calls the captured stand-in, and each call changes
        // the default. A second call came after the first change.
        let before = defaultChangingCalls.load(ordering: .relaxed)
        let horizon = try CelestialBody.sun.horizon(at: time, from: observer, refraction: .none)
        #expect(defaultChangingCalls.load(ordering: .relaxed) - before >= 2)

        // The stand-in returns the Espenak-Meeus bits, so the result is the
        // one a plain Espenak-Meeus time gives.
        let expected = try CelestialBody.sun.horizon(at: reference, from: observer, refraction: .none)
        #expect(horizon == expected)
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
        // the writers store. Install the stand-in and check it runs. Another
        // suite can restore the default between the two steps, so retry until
        // a construction calls the stand-in.
        var called = false
        for _ in 0..<1_000 where !called {
            Astronomy_SetDeltaTFunction(espenakMeeusStandIn)
            let callsBefore = standInCalls.load(ordering: .relaxed)
            _ = AstroTime(ut: ut)
            called = standInCalls.load(ordering: .relaxed) > callsBefore
        }
        #expect(called)
    }
}

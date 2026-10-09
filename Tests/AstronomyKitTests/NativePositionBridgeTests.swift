import CLibAstronomy
import Testing

@testable import AstronomyKit

private let positionCustomDeltaT: astro_deltat_func = { ut in 123.456 + 0.01 * ut }

@Suite("Geometric values with unnamed Delta-T callbacks")
struct NativePositionBridgeTests {
    @Test("Geometric positions preserve the original callback and scales")
    func customCallback() throws {
        var raw = Astronomy_MakeTime(2025, 1, 1, 0, 0, 0)
        raw.deltat_func = positionCustomDeltaT
        raw.tt = raw.ut + positionCustomDeltaT(raw.ut) / 86_400
        let time = AstroTime(raw: raw)
        #expect(time.deltaTModel == nil)
        for state in [
            try CelestialBody.mars.heliocentricState(at: time), try CelestialBody.moon.barycentricState(at: time),
        ] {
            #expect(state.time.universalTime == time.universalTime)
            #expect(state.time.terrestrialTime == time.terrestrialTime)
            #expect(state.time.deltaTModel == nil)
            #expect(state.time.addingDays(1).terrestrialTime == Astronomy_AddDays(raw, 1).tt)
        }
        let invalid = AstroTime(ut: .nan)
        #expect(throws: AstronomyError.badTime) { try CelestialBody.mars.geocentricPosition(at: invalid) }
    }
}

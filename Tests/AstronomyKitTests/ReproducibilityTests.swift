// Repeatability checks that survive the native cutover. The frozen C-engine
// bit patterns this suite used to hold were engine output, not published
// values; the published checks are in the JPL, USNO, NASA and SOFA suites.

import Testing

@testable import AstronomyKit

@Suite("Repeatability")
struct ReproducibilityTests {
    static let t2026 = AstroTime(year: 2_026, month: 7, day: 24, hour: 0, minute: 0, second: 0)

    @Test("Chiron positions repeat exactly across cache resets")
    func chironReproducibility() throws {
        let first = try Chiron.ecliptic(at: Self.t2026)
        #expect(try Chiron.ecliptic(at: Self.t2026) == first)
        AstronomyConfig.reset()
        #expect(try Chiron.ecliptic(at: Self.t2026) == first)
    }

    @Test("Phase-angle illumination at 45° is the half-cosine value")
    func illuminationAt45Degrees() {
        // (1 - cos 45°) / 2, a Swift-side expression with no engine input.
        let expected = Double(bitPattern: 0x3fc2_bec3_3301_8866)
        #expect(abs(Moon.illumination(for: 45.0) - expected) <= 1e-14)
    }
}

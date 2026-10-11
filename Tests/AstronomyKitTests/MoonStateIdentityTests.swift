import Foundation
import Testing

@testable import AstronomyKit

/// Public Moon identities and a Horizons event regression that
/// `BundledEphemerisTests` used to check through the C entry points.
@Suite("Moon state identity and events")
struct MoonStateIdentityTests {
    @Test("Moon state reports the position at the requested instant exactly")
    func moonStatePositionIdentity() throws {
        for tt in [-36_524.5, -123.25, 0, 12_345.625, 47_846.5, -60_000, 60_000] {
            let time = AstroTime(tt: tt)
            let position = try Moon.geocentricPosition(at: time)
            let state = try Moon.geoState(at: time)
            #expect(position.x.bitPattern == state.position.x.bitPattern, "tt \(tt)")
            #expect(position.y.bitPattern == state.position.y.bitPattern, "tt \(tt)")
            #expect(position.z.bitPattern == state.position.z.bitPattern, "tt \(tt)")
            #expect(state.time == time)
        }
    }

    @Test("Public lunar apsis and node searches retain the independent event direction and minute target")
    func lunarEventRegression() throws {
        // Lunar perigee and ascending node of 1903 July (TT), located from geometric
        // geocentric JPL Horizons DE441 Moon states; the node uses the IAU 2006 mean
        // ecliptic of date.
        let pericenter = 2_416_319.984182304 - 2_451_545.0
        let ascending = 2_416_324.69497546 - 2_451_545.0
        let apsis = try Moon.searchApsis(after: AstroTime(tt: pericenter - 3))
        #expect(apsis.kind == .pericenter)
        #expect(abs(apsis.time.terrestrialTime - pericenter) * 86_400 < 60)
        let node = try Moon.searchNode(after: AstroTime(tt: ascending - 3))
        #expect(node.kind == .ascending)
        #expect(abs(node.time.terrestrialTime - ascending) * 86_400 < 60)
    }
}

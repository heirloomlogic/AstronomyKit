import Testing

@testable import AstronomyKit

/// The public heliocentric position and state read the same planetary
/// representation at the polynomial coverage boundaries, and read it by TT.
@Suite("Polynomial ephemeris")
struct PolynomialTests {
    @Test("Position and state use the same representation at coverage boundaries")
    func positionAndStateAgree() throws {
        let boundaries = [-36_524.5, 0.0, 9_000.125, 36_889.5]
        let bodies: [CelestialBody] = [.mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune]
        for boundary in boundaries {
            for tt in [boundary.nextDown, boundary, boundary.nextUp] {
                // The UT is deliberately unrelated to the TT: only the TT selects the segment.
                let time = AstroTime(tt: tt, ut: 123, deltaTModel: .espenakMeeus)
                for body in bodies {
                    let position = try body.heliocentricPosition(at: time)
                    let state = try body.heliocentricState(at: time)
                    let distance = try body.distanceFromSun(at: time)
                    #expect(position.x.bitPattern == state.position.x.bitPattern, "\(body) at \(tt)")
                    #expect(position.y.bitPattern == state.position.y.bitPattern, "\(body) at \(tt)")
                    #expect(position.z.bitPattern == state.position.z.bitPattern, "\(body) at \(tt)")
                    #expect(state.time.terrestrialTime.bitPattern == tt.bitPattern)
                    #expect(position.time.universalTime == 123)
                    #expect(distance.isFinite && distance > 0)
                }
            }
        }
    }
}

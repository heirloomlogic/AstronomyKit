import CLibAstronomy
import Testing

@Suite("Polynomial ephemeris")
struct PolynomialTests {
    @Test("Position and state use the same representation at coverage boundaries")
    func positionAndStateAgree() {
        let boundaries = [-36_524.5, 0.0, 9_000.125, 36_889.5]
        let bodies = [
            BODY_MERCURY, BODY_VENUS, BODY_EARTH, BODY_MARS, BODY_JUPITER,
            BODY_SATURN, BODY_URANUS, BODY_NEPTUNE,
        ]
        for boundary in boundaries {
            for tt in [boundary.nextDown, boundary, boundary.nextUp] {
                let time = astro_time_t(ut: 123, tt: tt, psi: 0.125, eps: -0.25, st: 3)
                for body in bodies {
                    let position = Astronomy_HelioVector(body, time)
                    let state = Astronomy_HelioState(body, time)
                    let distance = Astronomy_HelioDistance(body, time)
                    #expect(position.status == ASTRO_SUCCESS)
                    #expect(state.status == ASTRO_SUCCESS)
                    #expect(distance.status == ASTRO_SUCCESS)
                    #expect(position.x.bitPattern == state.x.bitPattern)
                    #expect(position.y.bitPattern == state.y.bitPattern)
                    #expect(position.z.bitPattern == state.z.bitPattern)
                    #expect(state.t.tt.bitPattern == tt.bitPattern)
                    #expect(position.t.ut == 123)
                    #expect(state.t.psi == 0.125)
                    #expect(distance.value.isFinite && distance.value > 0)
                }
            }
        }
    }
}

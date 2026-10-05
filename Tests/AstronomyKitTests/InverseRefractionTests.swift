import Testing

@testable import AstronomyKit

@Suite("Inverse refraction termination")
struct InverseRefractionTests {
    static let modes: [Refraction] = [.none, .normal, .jplHorizons]
    static let neighborhoods: [Double] = [
        -90, Double(-90).nextDown, Double(-90).nextUp, -89.999_999_999_999, -89.999_999, -89.999, -89,
        90, Double(90).nextDown, Double(90).nextUp, 89.999_999_999_999, 89.999_999, 89.999, 89,
    ]

    @Test("Invalid apparent altitudes return no correction", arguments: modes)
    func invalid(mode: Refraction) {
        for altitude in [Double.nan, .infinity, -.infinity, -91, 91] {
            #expect(mode.inverseRefractionAngle(at: altitude) == 0)
        }
    }

    @Test("Endpoint neighborhoods terminate with finite correction", arguments: modes, neighborhoods)
    func endpoint(mode: Refraction, altitude: Double) {
        #expect(mode.inverseRefractionAngle(at: altitude).isFinite)
    }

    @Test("Known nonconvergent endpoints return no correction")
    func nonconvergentEndpoints() {
        #expect(Refraction.normal.inverseRefractionAngle(at: 90) == 0)
        #expect(Refraction.jplHorizons.inverseRefractionAngle(at: 90) == 0)
        #expect(Refraction.jplHorizons.inverseRefractionAngle(at: -90) == 0)
    }

    @Test("Successful inversions reproduce the apparent altitude", arguments: modes)
    func roundTrip(mode: Refraction) {
        for apparent in [-89.0, -45, -1, 0, 5, 30, 45, 89] {
            let correction = mode.inverseRefractionAngle(at: apparent)
            let geometric = apparent + correction
            #expect(abs(geometric + mode.refractionAngle(at: geometric) - apparent) < 1e-14)
        }
    }

    @Test("Horizontal caller retains supplied time and finite endpoint vectors", arguments: modes, DeltaTModel.allCases)
    func horizontal(mode: Refraction, model: DeltaTModel) {
        let time = AstroTime(ut: 10_000, deltaTModel: model)
        for altitude in Self.neighborhoods {
            let vector = Vector3D.from(
                horizon: Spherical(latitude: altitude, longitude: 123, distance: 2), at: time, refraction: mode)
            #expect(vector.x.isFinite && vector.y.isFinite && vector.z.isFinite)
            #expect(abs(vector.magnitude - 2) < 1e-14)
            #expect(vector.time == time)
            #expect(vector.time.deltaTModel == model)
        }
        let invalid = Vector3D.from(
            horizon: Spherical(latitude: .nan, longitude: 123, distance: 2), at: time, refraction: mode)
        #expect(invalid.x.isNaN && invalid.y.isNaN && invalid.z.isNaN)
        #expect(invalid.time == time)
    }
}

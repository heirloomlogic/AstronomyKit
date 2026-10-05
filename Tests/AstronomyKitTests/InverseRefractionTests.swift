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
        // No altitude in range refracts to this one: refraction drops to zero below -90 degrees.
        #expect(Refraction.jplHorizons.inverseRefractionAngle(at: -89.5) == 0)
    }

    /// Below -1 degree the normal model's forward map has slope above one, so it skips some doubles. From magnitude 64
    /// the spacing of doubles exceeds the 1e-14 tolerance, and the two neighbors that bracket a skipped altitude
    /// alternate without either meeting it.
    @Test("Normal mode returns an inverse within one ulp below -64 degrees")
    func straddledInverses() {
        let count = 200_000
        var failures: [Double] = []
        for index in 0..<count {
            let apparent = -90 + 26 * Double(index) / Double(count)
            let geometric = apparent + Refraction.normal.inverseRefractionAngle(at: apparent)
            if abs(geometric + Refraction.normal.refractionAngle(at: geometric) - apparent) > apparent.ulp {
                failures.append(apparent)
            }
        }
        #expect(failures.isEmpty, "\(failures.count) altitudes, first \(failures.prefix(3))")
    }

    @Test("Horizontal caller applies a straddled inverse", arguments: DeltaTModel.allCases)
    func straddledHorizontal(model: DeltaTModel) {
        let apparent = -69.320_219_183_602_32
        let correction = Refraction.normal.inverseRefractionAngle(at: apparent)
        let geometric = apparent + correction
        #expect(correction != 0)
        #expect(abs(geometric + Refraction.normal.refractionAngle(at: geometric) - apparent) <= apparent.ulp)
        let time = AstroTime(ut: 10_000, deltaTModel: model)
        let vector = Vector3D.from(
            horizon: Spherical(latitude: apparent, longitude: 123, distance: 2), at: time, refraction: .normal)
        let expected = Vector3D.from(
            horizon: Spherical(latitude: geometric, longitude: 123, distance: 2), at: time, refraction: .none)
        #expect(vector.x == expected.x && vector.y == expected.y && vector.z == expected.z)
        #expect(vector.time == time)
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

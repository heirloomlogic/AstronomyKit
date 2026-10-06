import Foundation
import Testing

@testable import AstronomyKit

/// The pre-repair inverse looped forever on six mode and altitude pairs, under both Delta T models and on both the
/// direct and the horizontal route.
///
/// A loop inside the C engine never reaches a cancellation point, so `.timeLimit` alone cannot stop it: the limit is
/// recorded only once the call returns. Each test therefore runs its work through ``terminating(_:)``, which abandons
/// a call that does not return in time and fails the test, so a hang is reported and the run continues. The suite
/// time limit stays as the backstop for anything that does return late.
@Suite("Inverse refraction termination", .timeLimit(.minutes(1)))
struct InverseRefractionTests {
    static let modes: [Refraction] = [.none, .normal, .jplHorizons]
    static let neighborhoods: [Double] = [
        -90, Double(-90).nextDown, Double(-90).nextUp, -89.999_999_999_999, -89.999_999, -89.999, -89,
        90, Double(90).nextDown, Double(90).nextUp, 89.999_999_999_999, 89.999_999, 89.999, 89,
    ]

    /// An apparent altitude from the 26-input termination protocol of issue #147, named as the protocol names it.
    struct ProtocolInput: Sendable, CustomTestStringConvertible {
        let name: String
        let altitude: Double
        var testDescription: String { name }
    }

    static let protocolInputs: [ProtocolInput] = [
        ("nan", .nan), ("-inf", -.infinity), ("inf", .infinity), ("-91", -91), ("91", 91),
        ("-90", -90), ("-90.nextDown", Double(-90).nextDown), ("-90.nextUp", Double(-90).nextUp),
        ("-89.999999999999", -89.999_999_999_999), ("-89.999999", -89.999_999), ("-89.999", -89.999), ("-89", -89),
        ("90", 90), ("90.nextDown", Double(90).nextDown), ("90.nextUp", Double(90).nextUp),
        ("89.999999999999", 89.999_999_999_999), ("89.999999", 89.999_999), ("89.999", 89.999), ("89", 89),
        ("-89.5", -89.5), ("-45", -45), ("-1", -1), ("0", 0), ("5", 5), ("30", 30), ("45", 45),
    ].map { ProtocolInput(name: $0, altitude: $1) }

    /// Inputs rejected before any iteration: nonfinite or outside [-90, 90].
    static let invalidInputs: Set<String> = ["nan", "-inf", "inf", "-91", "91"]

    /// Protocol inputs whose correction is +0.0 in each mode: the invalid inputs, plus the altitudes whose inversion
    /// cannot converge. Every other input must return a nonzero correction.
    static let zeroCorrections: [(mode: Refraction, names: Set<String>)] = [
        (.none, Set(protocolInputs.map(\.name))),
        (
            .normal,
            invalidInputs.union([
                "-90", "-90.nextDown", "-90.nextUp", "90", "90.nextDown", "90.nextUp", "89.999999999999", "89.999999",
            ])
        ),
        (
            .jplHorizons,
            invalidInputs.union([
                "-90", "-90.nextDown", "-90.nextUp", "-89.999999999999", "-89.999999", "-89.999",
                "90", "90.nextDown", "90.nextUp", "89.999999999999", "89.999999", "-89.5",
            ])
        ),
    ]

    /// Regression values, not independent truth: the correction bit patterns that the repaired source returned on
    /// Apple arm64 for every protocol input with a nonzero correction, recorded in the #147 measured execution
    /// (`InverseRefraction147/Evidence/current/raw-processes.json.gz`). The ulp-straddle repair left all of them
    /// unchanged.
    static let goldenCorrections: [(mode: Refraction, values: [String: UInt64])] = [
        (
            .normal,
            [
                "-89.999999999999": 0xbd10_0000_0000_0000, "-89.999999": 0xbe3e_fa48_0000_0000,
                "-89.999": 0xbede_406b_3000_0000, "-89": 0xbf7d_8ae8_acb6_4000, "89.999": 0x3f00_b22c_75e0_0000,
                "89": 0xbf31_52c2_344c_0000, "-89.5": 0xbf6d_8ae8_acb6_0000, "-45": 0xbfd4_c5ab_9970_1f00,
                "-1": 0xbfe4_8a95_c816_b2a8, "0": 0xbfe2_5d30_2204_8316, "5": 0xbfc5_29e6_af73_4740,
                "30": 0xbf9d_d529_e3e8_e800, "45": 0xbf91_4b2f_8dec_4800,
            ]
        ),
        (
            .jplHorizons,
            [
                "-89": 0xbfe4_b0c9_d79d_2a00, "89.999": 0x3f00_b22c_75e0_0000, "89": 0xbf31_52c2_344c_0000,
                "-45": 0xbfe4_b0c9_d79d_2a00, "-1": 0xbfe4_b0c9_d79d_29fe, "0": 0xbfe2_5d30_2204_8316,
                "5": 0xbfc5_29e6_af73_4740, "30": 0xbf9d_d529_e3e8_e800, "45": 0xbf91_4b2f_8dec_4800,
            ]
        ),
    ]

    /// Holds a result across threads. The semaphore that signals completion orders the write before the read.
    private final class Outcome<Value>: @unchecked Sendable {
        var value: Value?
    }

    /// Runs `body` on its own thread and returns its result, failing the test when it has not returned within 20
    /// seconds. A call that never returns is abandoned on its thread, which ends with the test process.
    static func terminating<Value>(_ body: @escaping @Sendable () -> Value) throws -> Value {
        let outcome = Outcome<Value>()
        let finished = DispatchSemaphore(value: 0)
        Thread {
            outcome.value = body()
            finished.signal()
        }.start()
        let returned = finished.wait(timeout: .now() + 20) == .success
        try #require(returned, "The inverse refraction call did not return within 20 seconds")
        return try #require(outcome.value)
    }

    @Test("Invalid apparent altitudes return a +0.0 correction", arguments: modes)
    func invalid(mode: Refraction) throws {
        let altitudes = [Double.nan, .infinity, -.infinity, -91, 91]
        let corrections = try Self.terminating { altitudes.map(mode.inverseRefractionAngle(at:)) }
        for (altitude, correction) in zip(altitudes, corrections) {
            #expect(correction.bitPattern == 0, "\(altitude) returned \(correction)")
        }
    }

    @Test("Exactly the expected protocol inputs return a +0.0 correction", arguments: zeroCorrections)
    func zeroCorrectionTable(mode: Refraction, names: Set<String>) throws {
        let corrections = try Self.terminating {
            Self.protocolInputs.map { mode.inverseRefractionAngle(at: $0.altitude) }
        }
        for (input, correction) in zip(Self.protocolInputs, corrections) {
            #expect(correction.isFinite, "\(input.name)")
            if names.contains(input.name) {
                #expect(correction.bitPattern == 0, "\(input.name) returned \(correction)")
            } else {
                #expect(correction != 0, "\(input.name) returned no correction")
            }
        }
    }

    /// Apple arm64 must reproduce the recorded bits. Other platforms' libm may round `tan` differently, which can move
    /// where the 1e-14 degree convergence test stops, so they get a small absolute allowance.
    @Test("Nonzero protocol corrections match the recorded regression bits", arguments: goldenCorrections)
    func goldenCorrectionTable(mode: Refraction, values: [String: UInt64]) throws {
        // Each protocol input is pinned once: to +0.0 in the zero table or to recorded bits here.
        let zeros = try #require(Self.zeroCorrections.first { $0.mode == mode }).names
        #expect(zeros.isDisjoint(with: values.keys))
        #expect(zeros.union(values.keys) == Set(Self.protocolInputs.map(\.name)))
        let corrections = try Self.terminating {
            Self.protocolInputs.map { mode.inverseRefractionAngle(at: $0.altitude) }
        }
        for (input, actual) in zip(Self.protocolInputs, corrections) {
            guard let bits = values[input.name] else { continue }
            let expected = Double(bitPattern: bits)
            #if canImport(Darwin) && arch(arm64)
            #expect(actual.bitPattern == bits, "\(input.name): \(actual) != \(expected)")
            #else
            #expect(abs(actual - expected) <= 1e-12, "\(input.name): \(actual) != \(expected)")
            #endif
        }
    }

    @Test("Endpoint neighborhoods terminate with finite correction", arguments: modes, neighborhoods)
    func endpoint(mode: Refraction, altitude: Double) throws {
        #expect(try Self.terminating { mode.inverseRefractionAngle(at: altitude) }.isFinite)
    }

    @Test("Known nonconvergent endpoints return no correction")
    func nonconvergentEndpoints() throws {
        let corrections = try Self.terminating {
            [
                Refraction.normal.inverseRefractionAngle(at: 90),
                Refraction.jplHorizons.inverseRefractionAngle(at: 90),
                Refraction.jplHorizons.inverseRefractionAngle(at: -90),
                // No altitude in range refracts to this one: refraction drops to zero below -90 degrees.
                Refraction.jplHorizons.inverseRefractionAngle(at: -89.5),
            ]
        }
        #expect(corrections.map(\.bitPattern) == [0, 0, 0, 0])
    }

    /// Below -1 degree the normal model's forward map has slope above one, so it skips some doubles. From magnitude 64
    /// the spacing of doubles exceeds the 1e-14 tolerance, and the two neighbors that bracket a skipped altitude
    /// alternate without either meeting it.
    @Test("Normal mode returns an inverse within one ulp below -64 degrees")
    func straddledInverses() throws {
        let failures = try Self.terminating {
            let count = 200_000
            var failures: [Double] = []
            for index in 0..<count {
                let apparent = -90 + 26 * Double(index) / Double(count)
                let geometric = apparent + Refraction.normal.inverseRefractionAngle(at: apparent)
                if abs(geometric + Refraction.normal.refractionAngle(at: geometric) - apparent) > apparent.ulp {
                    failures.append(apparent)
                }
            }
            return failures
        }
        #expect(failures.isEmpty, "\(failures.count) altitudes, first \(failures.prefix(3))")
    }

    @Test("Horizontal caller applies a straddled inverse", arguments: DeltaTModel.allCases)
    func straddledHorizontal(model: DeltaTModel) throws {
        let apparent = -69.320_219_183_602_32
        let time = AstroTime(ut: 10_000, deltaTModel: model)
        let (correction, vector) = try Self.terminating {
            (
                Refraction.normal.inverseRefractionAngle(at: apparent),
                Vector3D.from(
                    horizon: Spherical(latitude: apparent, longitude: 123, distance: 2), at: time, refraction: .normal)
            )
        }
        let geometric = apparent + correction
        #expect(correction != 0)
        #expect(abs(geometric + Refraction.normal.refractionAngle(at: geometric) - apparent) <= apparent.ulp)
        let expected = Vector3D.from(
            horizon: Spherical(latitude: geometric, longitude: 123, distance: 2), at: time, refraction: .none)
        #expect(vector.x == expected.x && vector.y == expected.y && vector.z == expected.z)
        #expect(vector.time == time)
    }

    @Test("Successful inversions reproduce the apparent altitude", arguments: modes)
    func roundTrip(mode: Refraction) throws {
        let apparents = [-89.0, -45, -1, 0, 5, 30, 45, 89]
        let corrections = try Self.terminating { apparents.map(mode.inverseRefractionAngle(at:)) }
        for (apparent, correction) in zip(apparents, corrections) {
            let geometric = apparent + correction
            #expect(abs(geometric + mode.refractionAngle(at: geometric) - apparent) < 1e-14)
        }
    }

    /// The horizontal caller removes refraction by adding exactly the direct correction, including a zero correction
    /// for invalid or nonconvergent inputs, and keeps the supplied time.
    @Test(
        "Horizontal caller applies the direct correction to every protocol input", arguments: modes,
        DeltaTModel.allCases)
    func horizontalProtocol(mode: Refraction, model: DeltaTModel) throws {
        let time = AstroTime(ut: 10_000, deltaTModel: model)
        let results = try Self.terminating {
            Self.protocolInputs.map { input in
                (
                    correction: mode.inverseRefractionAngle(at: input.altitude),
                    vector: Vector3D.from(
                        horizon: Spherical(latitude: input.altitude, longitude: 123, distance: 2), at: time,
                        refraction: mode)
                )
            }
        }
        for (input, result) in zip(Self.protocolInputs, results) {
            let vector = result.vector
            let expected = Vector3D.from(
                horizon: Spherical(latitude: input.altitude + result.correction, longitude: 123, distance: 2), at: time,
                refraction: .none)
            #expect(
                [vector.x, vector.y, vector.z].map(\.bitPattern)
                    == [expected.x, expected.y, expected.z].map(\.bitPattern),
                "\(input.name)")
            #expect(vector.time == time, "\(input.name)")
            #expect(vector.time.universalTime.bitPattern == time.universalTime.bitPattern, "\(input.name)")
            #expect(vector.time.terrestrialTime.bitPattern == time.terrestrialTime.bitPattern, "\(input.name)")
            #expect(vector.time.deltaTModel == model, "\(input.name)")
        }
    }

    @Test("Horizontal caller retains supplied time and finite endpoint vectors", arguments: modes, DeltaTModel.allCases)
    func horizontal(mode: Refraction, model: DeltaTModel) throws {
        let time = AstroTime(ut: 10_000, deltaTModel: model)
        let (vectors, invalid) = try Self.terminating {
            (
                Self.neighborhoods.map {
                    Vector3D.from(
                        horizon: Spherical(latitude: $0, longitude: 123, distance: 2), at: time, refraction: mode)
                },
                Vector3D.from(
                    horizon: Spherical(latitude: .nan, longitude: 123, distance: 2), at: time, refraction: mode)
            )
        }
        for vector in vectors {
            #expect(vector.x.isFinite && vector.y.isFinite && vector.z.isFinite)
            #expect(abs(vector.magnitude - 2) < 1e-14)
            #expect(vector.time == time)
            #expect(vector.time.deltaTModel == model)
        }
        #expect(invalid.x.isNaN && invalid.y.isNaN && invalid.z.isNaN)
        #expect(invalid.time == time)
    }
}

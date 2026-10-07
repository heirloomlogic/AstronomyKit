import Foundation
import Testing

@testable import AstronomyKit

/// The held-out distance fixture, shared with the engine planet tests.
struct DistanceReferenceArchive: Decodable {
    let references: [Reference]

    struct Reference: Decodable, Sendable {
        let body: String
        let mode: String
        let julianDateTT: Double
        let referenceRangeAU: Double
        let referencePositionAU: [Double]
        let allowedErrorKm: Double
    }

    static let shared: Self = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/IndependentReferences/distance-fixtures.json")
        do {
            return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Invalid independent distance fixture: \(error)")
        }
    }()
}

@Suite("Finite independent distance allowances")
struct DistanceAccuracyTests {
    @Test(
        "Held-out heliocentric radius and matched geocentric range",
        arguments: DistanceReferenceArchive.shared.references)
    fileprivate func heldOutDistance(reference: DistanceReferenceArchive.Reference) throws {
        let body = try #require(CelestialBody.allCases.first { $0.name == reference.body })
        let time = AstroTime(tt: reference.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
        let actual: Double
        if reference.mode == "heliocentric" {
            actual = try body.distanceFromSun(at: time)
        } else {
            #expect(reference.mode == "geocentric")
            actual = try body.geocentricPosition(at: time, aberration: .none).magnitude
        }
        let errorKm = abs(actual - reference.referenceRangeAU) * 149_597_870.7
        #expect(
            errorKm <= reference.allowedErrorKm,
            "\(reference.body) \(reference.mode), JDTT \(reference.julianDateTT): \(errorKm) km; allowance \(reference.allowedErrorKm) km"
        )
    }

    @Test("Distance comparisons reject unit and observer-selection mistakes")
    func negativeControls() throws {
        let references = DistanceReferenceArchive.shared.references
        let selected = try #require(references.first { $0.body == "Mercury" && $0.mode == "heliocentric" })
        let time = AstroTime(tt: selected.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
        let radius = try CelestialBody.mercury.distanceFromSun(at: time)
        let wrongOrigin = try CelestialBody.mercury.geocentricPosition(at: time, aberration: .none).magnitude
        #expect(abs(radius * 1_000 - selected.referenceRangeAU) * 149_597_870.7 > selected.allowedErrorKm)
        #expect(abs(wrongOrigin - selected.referenceRangeAU) * 149_597_870.7 > selected.allowedErrorKm)
        let wrongEpoch = try CelestialBody.mercury.distanceFromSun(at: time.addingDays(1))
        #expect(abs(wrongEpoch - selected.referenceRangeAU) * 149_597_870.7 > selected.allowedErrorKm)
        #expect(abs(-radius - selected.referenceRangeAU) * 149_597_870.7 > selected.allowedErrorKm)
        let received = try #require(references.first { $0.body == "Mercury" && $0.mode == "geocentric" })
        let reception = AstroTime(tt: received.julianDateTT - 2_451_545, deltaTModel: .jplHorizons)
        let defaultAberrationRange = try CelestialBody.mercury.geocentricPosition(at: reception).magnitude
        #expect(abs(defaultAberrationRange - received.referenceRangeAU) * 149_597_870.7 > received.allowedErrorKm)
    }
}

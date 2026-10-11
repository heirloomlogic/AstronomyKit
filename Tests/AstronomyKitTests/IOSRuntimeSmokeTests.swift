#if os(iOS)
import Foundation
import Testing

@testable import AstronomyKit

@Suite("iOS runtime smoke")
struct IOSRuntimeSmokeTests {
    @Test("Public Sun position matches the published JPL value")
    func publishedSunPosition() throws {
        let time = AstroTime(year: 2026, month: 1, day: 2, deltaTModel: .espenakMeeus)
        let position = try CelestialBody.sun.equatorial(
            at: time,
            from: .geocentric,
            equatorDate: .j2000
        )
        let expectedRightAscension = 18.0 + 48.0 / 60.0 + 50.13 / 3_600.0
        let expectedDeclination = -(22.0 + 57.0 / 60.0 + 40.4 / 3_600.0)
        let separation = angularSeparationArcminutes(
            rightAscension: position.rightAscension,
            declination: position.declination,
            expectedRightAscension: expectedRightAscension,
            expectedDeclination: expectedDeclination
        )

        #expect(position.distance.isFinite && position.distance > 0)
        #expect(separation <= 1.0, "iOS Sun position differs from the published JPL value by \(separation) arcminutes")
    }

    private func angularSeparationArcminutes(
        rightAscension: Double,
        declination: Double,
        expectedRightAscension: Double,
        expectedDeclination: Double
    ) -> Double {
        let ra = rightAscension * 15 * .pi / 180
        let expectedRA = expectedRightAscension * 15 * .pi / 180
        let dec = declination * .pi / 180
        let expectedDec = expectedDeclination * .pi / 180
        let cosine = sin(dec) * sin(expectedDec) + cos(dec) * cos(expectedDec) * cos(ra - expectedRA)
        return acos(min(1, max(-1, cosine))) * 180 / .pi * 60
    }
}
#endif

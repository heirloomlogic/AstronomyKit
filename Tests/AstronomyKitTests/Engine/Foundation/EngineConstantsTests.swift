//
//  EngineConstantsTests.swift
//  AstronomyKit
//
//  The shared numeric constants against their published definitions.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine constants")
struct EngineConstantsTests {
    /// π to 40 decimal places; `Decimal` keeps 38 significant digits.
    static let pi = Decimal(string: "3.1415926535897932384626433832795028841971")!

    /// The double nearest `value`, through Swift's correctly rounded parse
    /// of its decimal digits.
    static func nearest(_ value: Decimal) -> Double {
        Double("\(value)")!
    }

    @Test("A day is 86,400 seconds")
    func secondsPerDay() {
        #expect(Engine.secondsPerDay == 86_400)
    }

    /// IAU 2012 Resolution B2.
    @Test("The au is exactly 149,597,870,700 m")
    func astronomicalUnit() {
        #expect(Engine.kilometersPerAU == Self.nearest(Decimal(149_597_870_700) / 1_000))
    }

    /// 299,792,458 m/s is exact in the SI.
    @Test("The speed of light is 299,792,458 m/s times 86,400 s over the au")
    func speedOfLight() {
        let exact = Decimal(299_792_458) * 86_400 / Decimal(149_597_870_700)
        #expect(Engine.speedOfLightAUPerDay == Self.nearest(exact))
    }

    /// The IAU 2009 System of Astronomical Constants gives the light time for
    /// one au as 499.004 783 836(10) s.
    @Test("Light crosses one au in the IAU's 499.004 783 836 s")
    func lightTimePerAU() {
        let seconds = Engine.secondsPerDay / Engine.speedOfLightAUPerDay
        #expect(abs(seconds - 499.004_783_836) < 1e-9)
    }

    @Test(
        "Each angle factor is the double nearest its expression in π",
        arguments: [
            ("π/180", Engine.radiansPerDegree, pi / 180),
            ("180/π", Engine.degreesPerRadian, 180 / pi),
            ("π/12", Engine.radiansPerHour, pi / 12),
            ("12/π", Engine.hoursPerRadian, 12 / pi),
            ("π/648000", Engine.radiansPerArcsecond, pi / 648_000),
        ])
    func angleFactor(name: String, value: Double, exact: Decimal) {
        #expect(value == Self.nearest(exact), "\(name)")
    }

    @Test("The angle factors invert each other to within one rounding")
    func angleFactorsInvert() {
        #expect(abs(Engine.radiansPerDegree * Engine.degreesPerRadian - 1) <= Double.ulpOfOne)
        #expect(abs(Engine.radiansPerHour * Engine.hoursPerRadian - 1) <= Double.ulpOfOne)
        #expect(abs(Engine.radiansPerArcsecond * 3_600 - Engine.radiansPerDegree) <= Engine.radiansPerDegree.ulp)
    }
}

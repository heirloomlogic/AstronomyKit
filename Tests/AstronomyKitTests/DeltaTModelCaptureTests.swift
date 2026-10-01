import Foundation
import Testing

@testable import AstronomyKit

/// Every time value carries the Delta T model that produced it, and every
/// time derived from it uses the same model. These tests never change the
/// process default, so they can run beside any other suite.
@Suite("Delta T model capture")
struct DeltaTModelCaptureTests {
    private static let observer40N = Observer(latitude: 40, longitude: 0)

    /// The TT the engine derives from `ut` under `model`.
    private static func tt(ut: Double, under model: DeltaTModel) -> Double {
        ut + model.function(ut) / 86_400
    }

    /// True when `time` carries `model` and its TT was derived from its UT by
    /// that model, as every derived time is.
    private static func derived(_ time: AstroTime, under model: DeltaTModel) -> Bool {
        time.deltaTModel == model && time.terrestrialTime == tt(ut: time.universalTime, under: model)
    }

    @Test("A value's model does not depend on the process default")
    func perValueModel() {
        let ut = 36_525.0
        let jpl = AstroTime(ut: ut, deltaTModel: .jplHorizons)
        #expect(jpl.universalTime == ut)
        #expect(Self.derived(jpl, under: .jplHorizons))

        let em = AstroTime(ut: ut, deltaTModel: .espenakMeeus)
        #expect(Self.derived(em, under: .espenakMeeus))
        #expect(jpl.terrestrialTime != em.terrestrialTime)

        // The process default is still Espenak-Meeus.
        #expect(AstroTime(ut: ut).terrestrialTime == em.terrestrialTime)
    }

    @Test("The TT inverse runs under the value's model")
    func terrestrialInverse() {
        let tt = 36_525.0
        // Astronomy_TerrestrialTime accepts 2 ulp of |tt| as converged.
        let tolerance = 2 * Double.ulpOfOne * tt

        let jpl = AstroTime(tt: tt, deltaTModel: .jplHorizons)
        #expect(jpl.terrestrialTime == tt)
        #expect(jpl.deltaTModel == .jplHorizons)
        #expect(abs(tt - Self.tt(ut: jpl.universalTime, under: .jplHorizons)) <= tolerance)

        let em = AstroTime(tt: tt, deltaTModel: .espenakMeeus)
        #expect(em.terrestrialTime == tt)
        #expect(abs(tt - Self.tt(ut: em.universalTime, under: .espenakMeeus)) <= tolerance)
        #expect(jpl.universalTime != em.universalTime)
    }

    @Test("A civil date keeps TT and changes UT with the model: 2049-12-21T12:00Z")
    func civilDateAcrossModels() throws {
        let date = try #require(ISO8601DateFormatter().date(from: "2049-12-21T12:00:00Z"))
        let em = AstroTime(date, deltaTModel: .espenakMeeus)
        let jpl = AstroTime(date, deltaTModel: .jplHorizons)
        #expect(em.deltaTModel == .espenakMeeus)
        #expect(jpl.deltaTModel == .jplHorizons)

        // Civil UTC fixes TT through the offset table; only UT follows the model.
        #expect(em.terrestrialTime == jpl.terrestrialTime)
        let utShiftSeconds = (jpl.universalTime - em.universalTime) * 86_400
        #expect(abs(utShiftSeconds - 22.950380633) < 1e-6)

        // Geometric solar altitude at 40N 0E. Measured here as 5.216569e-4
        // degrees; #49 reports 5.21646698e-4 at an earlier revision. The
        // tolerance admits native-libm differences between platforms.
        let emAltitude = try CelestialBody.sun.horizon(at: em, from: Self.observer40N, refraction: .none).altitude
        let jplAltitude = try CelestialBody.sun.horizon(at: jpl, from: Self.observer40N, refraction: .none).altitude
        #expect(abs((emAltitude - jplAltitude) - 0.000_521_657) < 1e-7)

        // Calendar components reach the same value.
        let components = AstroTime(year: 2_049, month: 12, day: 21, hour: 12, deltaTModel: .jplHorizons)
        #expect(components.deltaTModel == .jplHorizons)
        #expect(components.terrestrialTime == jpl.terrestrialTime)
        #expect(components.universalTime == jpl.universalTime)
    }

    @Test("A pair of scales is stored exactly and carries the model")
    func pairInit() {
        let tt = 18_262.000_744
        let ut = 18_261.999_999
        let time = AstroTime(tt: tt, ut: ut, deltaTModel: .jplHorizons)
        #expect(time.terrestrialTime == tt)
        #expect(time.universalTime == ut)
        #expect(time.deltaTModel == .jplHorizons)

        let later = time.addingDays(1)
        #expect(later.universalTime == ut + 1)
        #expect(Self.derived(later, under: .jplHorizons))

        // Without a model, the pair uses the process default.
        let plain = AstroTime(tt: tt, ut: ut)
        #expect(plain.terrestrialTime == tt)
        #expect(plain.universalTime == ut)
        #expect(plain.addingDays(1).terrestrialTime == Self.tt(ut: ut + 1, under: .espenakMeeus))
    }

    @Test("A non-finite scale makes an invalid time that calculations reject")
    func pairInitRejectsNonFinite() {
        let pairs: [(tt: Double, ut: Double)] = [(.nan, 0), (0, .nan), (.infinity, 0), (0, -.infinity)]
        for pair in pairs {
            let time = AstroTime(tt: pair.tt, ut: pair.ut)
            #expect(time.terrestrialTime.isNaN)
            #expect(time.universalTime.isNaN)
            #expect(time.deltaTModel == nil)
            #expect(throws: AstronomyError.badTime) { try Sun.position(at: time) }
            #expect(throws: AstronomyError.badTime) {
                try CelestialBody.sun.horizon(at: time, from: Self.observer40N)
            }
        }
    }

    @Test("Derived times and search results keep the model")
    func derivedTimesKeepModel() throws {
        let start = AstroTime(year: 2_030, month: 6, day: 1, deltaTModel: .jplHorizons)
        #expect(Self.derived(start.addingHours(6), under: .jplHorizons))

        // Astronomy_Search: bisection and quadratic interpolation steps.
        let rise = try #require(try CelestialBody.sun.riseTime(after: start, from: .greenwich))
        #expect(Self.derived(rise, under: .jplHorizons))
        let mars = try CelestialBody.mars.searchApsis(after: start)
        #expect(Self.derived(mars.time, under: .jplHorizons))

        // The brute-force apsis search samples times from a UT grid.
        let neptune = try CelestialBody.neptune.searchApsis(after: start)
        #expect(Self.derived(neptune.time, under: .jplHorizons))

        // The default model is unchanged by any of the above.
        let plainRise = try #require(try CelestialBody.sun.riseTime(after: AstroTime(year: 2_030, month: 6, day: 1), from: .greenwich))
        #expect(Self.derived(plainRise, under: .espenakMeeus))
        #expect(plainRise.universalTime != rise.universalTime)
    }

    @Test("Equality, hashing and Codable ignore the model")
    func equalityAndCodable() throws {
        let jpl = AstroTime(ut: 1, deltaTModel: .jplHorizons)
        let em = AstroTime(ut: 1, deltaTModel: .espenakMeeus)
        #expect(jpl == em)
        #expect(jpl.hashValue == em.hashValue)

        let decoded = try JSONDecoder().decode(AstroTime.self, from: JSONEncoder().encode(jpl))
        #expect(decoded.universalTime == 1)
        #expect(decoded.terrestrialTime == Self.tt(ut: 1, under: .espenakMeeus))
    }
}

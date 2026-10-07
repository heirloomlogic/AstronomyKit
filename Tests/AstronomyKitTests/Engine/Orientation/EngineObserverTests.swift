//
//  EngineObserverTests.swift
//  AstronomyKit
//
//  Observer positions, states, their inverse and gravity against SOFA and
//  the published ellipsoid and gravity formulas.
//

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.Observers")
struct EngineObserverTests {
    typealias Observers = Engine.Observers

    static let time = Engine.Time(ut: 9_496.374_023_437_5, tt: 9_496.375, deltaTModel: .espenakMeeus)

    /// Earth-fixed coordinates of an equator-of-date vector, turned back by
    /// apparent sidereal time (checked against SOFA in
    /// `EngineEarthRotationTests`), in metres.
    static func earthFixed(_ v: Engine.Vector<Engine.EQD>) -> [Double] {
        let theta = Engine.EarthRotation.apparentSiderealTime(v.time) * Engine.radiansPerHour
        let metres = Engine.kilometersPerAU * 1000
        return [
            (v.x * cos(theta) + v.y * sin(theta)) * metres,
            (-v.x * sin(theta) + v.y * cos(theta)) * metres,
            v.z * metres,
        ]
    }

    /// pyerfa 2.0.1.5 `gd2gce(6378136.6, 1/298.25642, elong, phi, height)`:
    /// SOFA's geodetic-to-geocentric conversion on the IERS Conventions
    /// (2010) Table 1.1 ellipsoid. Latitude and longitude in degrees, height
    /// and the Earth-fixed position in metres.
    static let geodetic: [(latitude: Double, longitude: Double, height: Double, xyz: [Double])] = [
        (0, 0, 0, [6_378_136.6, 0, 0]),
        (35.6, -82.55, 650, [673_262.971_538_915_8, -5_148_655.626_862_971, 3_692_573.111_273_841]),
        (-51.5, 170.25, 8_848.86, [-3_926_609.921_826_678, 674_714.985_472_805_1, -4_975_287.273_165_441]),
        (89.5, 12, -500, [54_621.620_853_060_09, 11_610.183_921_370_031, 6_356_008.200_201_168]),
        (90, 0, 1_000, [3.919_233_037_977_285e-10, 0, 6_357_751.857_971_647]),
        (-90, 45, 0, [2.770_883_280_175_975e-10, 2.770_883_280_175_974_3e-10, -6_356_751.857_971_647]),
        (-33.9, 18.4, 2_000_000, [6_603_680.978_553_896, 2_196_752.279_124_313, -4_652_735.289_836_192]),
    ]

    /// 1e-6 m: the conversion through AU and back loses about 1e-9 m at
    /// Earth-radius scale.
    @Test("Positions are SOFA's gd2gce on the IERS 2010 ellipsoid", arguments: geodetic.indices)
    func geodeticPosition(index: Int) {
        let c = Self.geodetic[index]
        let observer = Observer(latitude: c.latitude, longitude: c.longitude, height: c.height)
        let fixed = Self.earthFixed(Observers.vectorOfDate(observer, at: Self.time))
        for axis in 0..<3 {
            #expect(abs(fixed[axis] - c.xyz[axis]) <= 1e-6, "axis \(axis): \(fixed[axis]) m")
        }
    }

    @Test("The J2000 position and state are the of-date ones rotated", arguments: geodetic.indices)
    func j2000(index: Int) {
        let c = Self.geodetic[index]
        let observer = Observer(latitude: c.latitude, longitude: c.longitude, height: c.height)
        let rotation = Engine.FrameRotation.eqdToEqj(Self.time)
        let ofDate = Observers.vectorOfDate(observer, at: Self.time)
        let expected = rotation.apply(to: ofDate)
        let j2000 = Observers.vector(observer, at: Self.time)
        #expect((j2000.x, j2000.y, j2000.z) == (expected.x, expected.y, expected.z))
        let state = Observers.state(observer, at: Self.time)
        let expectedState = rotation.apply(to: Observers.stateOfDate(observer, at: Self.time))
        #expect((state.vx, state.vy, state.vz) == (expectedState.vx, expectedState.vy, expectedState.vz))
        #expect((state.x, state.y, state.z) == (j2000.x, j2000.y, j2000.z))
    }

    /// The velocity is ω × r with the IERS 2010 nominal ω. The position turns
    /// with apparent sidereal time, whose rate differs from ω by 1.2e-8 for
    /// the Earth rotation angle and by up to about 1.3e-7 for the nutation
    /// in the equation of the equinoxes, so a five-point difference of the
    /// position agrees to within 5e-7 of the speed.
    @Test("Velocity is the Earth's rotation crossed into the position")
    func velocity() {
        let observer = Observer(latitude: 35.6, longitude: -82.55, height: 650)
        let state = Observers.stateOfDate(observer, at: Self.time)
        let speed = 7.292_115e-5 * 86_400
        let speedNow = hypot(state.vx, state.vy)
        #expect(abs(state.vx + speed * state.y) <= 1e-15 * speedNow)
        #expect(abs(state.vy - speed * state.x) <= 1e-15 * speedNow)
        #expect(state.vz == 0)

        let step = 1.0 / 1024
        func position(_ dt: Double) -> Engine.Vector<Engine.EQD> {
            let t = Engine.Time(ut: Self.time.ut + dt, tt: Self.time.tt + dt, deltaTModel: .espenakMeeus)
            return Observers.vectorOfDate(observer, at: t)
        }
        let dx = PublishedOrientation.derivative(at: 0, step: step) { position($0).x }
        let dy = PublishedOrientation.derivative(at: 0, step: step) { position($0).y }
        #expect(abs(dx - state.vx) <= 5e-7 * speedNow)
        #expect(abs(dy - state.vy) <= 5e-7 * speedNow)
    }

    /// pyerfa 2.0.1.5 `gc2gde(6378136.6, 1/298.25642, xyz)`: SOFA's
    /// geocentric-to-geodetic conversion, Earth-fixed metres in, latitude
    /// and longitude in degrees and height in metres out.
    static let geocentric: [(xyz: [Double], latitude: Double, longitude: Double, height: Double)] = [
        ([2_000_000, 3_000_000, 5_244_000], 55.668_685_739_791_61, 56.309_932_474_020_215, 331.855_579_166_300_3),
        (
            [-4_500_000, 1_200_000, -4_100_000],
            -41.554_994_936_170_516, 165.068_582_821_862_46, -163_935.255_216_619_93
        ),
        ([6_400_000, 0, 1], 9.012_593_325_631_574e-6, 0, 21_863.400_000_078_775),
    ]

    /// The engine stops Newton's method when the ellipsoid error is below
    /// 2e-8 km, as the C engine does, so the height and latitude agree with
    /// SOFA's closed form to about a millimetre.
    @Test("The inverse is SOFA's gc2gde on the IERS 2010 ellipsoid", arguments: geocentric.indices)
    func inverse(index: Int) {
        let c = Self.geocentric[index]
        let theta = Engine.EarthRotation.apparentSiderealTime(Self.time) * Engine.radiansPerHour
        let au = Engine.kilometersPerAU * 1000
        let vector = Engine.Vector<Engine.EQD>(
            x: (c.xyz[0] * cos(theta) - c.xyz[1] * sin(theta)) / au,
            y: (c.xyz[0] * sin(theta) + c.xyz[1] * cos(theta)) / au,
            z: c.xyz[2] / au,
            time: Self.time
        )
        let observer = Observers.observer(atVectorOfDate: vector)
        #expect(abs(observer.latitude - c.latitude) <= 1e-9)
        let longitude = (observer.longitude - c.longitude) * Engine.radiansPerDegree
        #expect(abs(PublishedOrientation.wrapped(longitude)) <= 1e-12)
        #expect(abs(observer.height - c.height) <= 1e-3)
    }

    @Test("Round trips through the J2000 vector", arguments: geodetic.indices)
    func roundTrip(index: Int) {
        let c = Self.geodetic[index]
        let observer = Observer(latitude: c.latitude, longitude: c.longitude, height: c.height)
        let back = Observers.observer(atVector: Observers.vector(observer, at: Self.time))
        #expect(abs(back.latitude - c.latitude) <= 1e-8)
        #expect(abs(back.height - c.height) <= 1e-3)
        if abs(c.latitude) < 90 {
            let longitude = (back.longitude - c.longitude) * Engine.radiansPerDegree
            #expect(abs(PublishedOrientation.wrapped(longitude)) <= 1e-12)
            #expect(back.longitude > -180 && back.longitude <= 180)
        } else {
            #expect(back.longitude == 0)
        }
    }

    @Test("Within a millimetre of the axis the latitude is ±90 and the longitude 0", arguments: [1.0, -1.0])
    func nearAxis(sign: Double) {
        let au = Engine.kilometersPerAU
        let polar = 6_378.136_6 * (1 - 1 / 298.256_42)
        let vector = Engine.Vector<Engine.EQD>(x: 1e-7 / au, y: 0, z: sign * (polar + 2) / au, time: Self.time)
        let observer = Observers.observer(atVectorOfDate: vector)
        #expect(observer.latitude == 90 * sign)
        #expect(observer.longitude == 0)
        #expect(abs(observer.height - 2_000) <= 1e-6)
    }

    /// The non-finite value goes in each component in turn, with the others
    /// zero (on the axis, for z) or at a surface point.
    @Test(
        "A vector that is not finite gives a NaN observer instead of stopping",
        arguments: [Double.nan, .infinity, -.infinity], 0..<3
    )
    func nonfinite(value: Double, axis: Int) {
        let surface = 6_378_136.6e-3 / Engine.kilometersPerAU
        for base in [[0.0, 0, 0], [surface, 0, 0]] {
            var c = base
            c[axis] = value
            let vector = Engine.Vector<Engine.EQD>(x: c[0], y: c[1], z: c[2], time: Self.time)
            let observer = Observers.observer(atVectorOfDate: vector)
            #expect(observer.latitude.isNaN, "\(c)")
            #expect(observer.longitude.isNaN, "\(c)")
            #expect(observer.height.isNaN, "\(c)")
        }
    }

    /// `Observer.geocentric` is the ellipsoid's equatorial radius below the
    /// surface at latitude 0, so its vector is exactly zero (#154).
    @Test("The geocentric observer is at the centre")
    func geocentricObserver() {
        let ofDate = Observers.vectorOfDate(.geocentric, at: Self.time)
        #expect(ofDate.length == 0)
        #expect(Observers.vector(.geocentric, at: Self.time).length == 0)
        let state = Observers.stateOfDate(.geocentric, at: Self.time)
        #expect(hypot(state.vx, state.vy) == 0)
    }

    /// NIMA TR8350.2 (WGS 84), equation 4-1 (Somigliana) and equation 4-3,
    /// transcribed with the report's defining parameters rather than the
    /// engine's coefficients: γe = 9.7803253359 m/s², k = 0.00193185265241,
    /// e² = 0.00669437999013, a = 6378137 m, f = 1/298.257223563 and
    /// m = ω²a²b/GM = 0.00344978650684.
    static func normalGravity(latitude: Double, height: Double) -> Double {
        let s2 = pow(sin(latitude * .pi / 180), 2)
        let surface = 9.780_325_335_9 * (1 + 0.001_931_852_652_41 * s2) / (1 - 0.006_694_379_990_13 * s2).squareRoot()
        let a = 6_378_137.0
        let f = 1 / 298.257_223_563
        let m = 0.003_449_786_506_84
        return surface * (1 - 2 / a * (1 + f + m - 2 * f * s2) * height + 3 / (a * a) * height * height)
    }

    /// 1e-9 m/s² plus 5e-12 m/s² per metre: the engine's height coefficients
    /// are the report's rounded to six figures.
    @Test(
        "Gravity is the WGS 84 normal gravity",
        arguments: [(0.0, 0.0), (45, 1_000), (-60, 8_848.86), (90, 0), (-90, 20_000), (12.5, -400)]
    )
    func gravity(latitude: Double, height: Double) {
        let expected = Self.normalGravity(latitude: latitude, height: height)
        let actual = Observers.gravity(latitude: latitude, height: height)
        #expect(abs(actual - expected) <= 1e-9 + 5e-12 * abs(height))
    }
}

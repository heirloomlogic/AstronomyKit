//
//  EngineRotationAxis.swift
//  AstronomyKit
//
//  The orientation of a body's rotation axis and prime meridian.
//

import Foundation

extension Engine {
    /// A body's north pole and prime meridian at one time.
    struct Axis: Sendable {
        /// The north pole's right ascension in sidereal hours and declination
        /// in degrees, on the mean equator and equinox of J2000.
        var rightAscension: Double
        var declination: Double
        /// The prime meridian's angle W in degrees, measured along the body's
        /// equator, counterclockwise as seen from the north pole, from the
        /// equator's ascending node on the J2000 equator, which is at right
        /// ascension α0 + 90°. It is not reduced to one turn.
        ///
        /// Earth's is the exception, as in the C engine: its pole is the true
        /// pole of date, but its W is the 2009 report's, measured from the
        /// node of the report's own Earth pole and re-expressed on UT. The
        /// two together do not place Greenwich.
        var spin: Double
        /// The unit vector toward the north pole.
        var north: Vector<EQJ>
    }

    /// Rotation axes (`Astronomy_RotationAxis`).
    ///
    /// Every body but Earth follows the IAU Working Group on Cartographic
    /// Coordinates and Rotational Elements: its 2015 report (Archinal et al.
    /// 2018, Celest. Mech. Dyn. Astr. 130:22), and its 2009 report (Archinal
    /// et al. 2011, 109:101) for the Moon, which the 2015 report does not
    /// cover. The expressions take d in TDB days and T in Julian centuries of
    /// TDB from J2000, as the reports define them.
    ///
    /// Earth keeps the C engine's model. Its pole is the true pole of date
    /// from the IAU 2006 precession and IAU 2000B nutation
    /// (``Engine/FrameRotation``). Its W is ``earthSpinAtJ2000`` plus
    /// ``earthSpinRate`` per UT day: the 2009 report's W at J2000,
    /// 190.147°, moved onto UT with a Delta T of about 63.85 s, turning at the
    /// rate of the Earth rotation angle (IAU 2000 Resolution B1.8).
    enum RotationAxis {}
}

extension Engine.RotationAxis {
    /// The bodies the reports and Earth's model cover.
    static let bodies: [CelestialBody] = [
        .sun, .mercury, .venus, .earth, .moon, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
    ]

    /// Earth's W at UT 0, J2000, in degrees.
    static let earthSpinAtJ2000 = 190.41375788700253

    /// Earth's W rate in degrees per UT day: 360° times the Earth rotation
    /// angle's 1.00273781191135448 turns per UT day.
    static let earthSpinRate = 360.9856122880876

    /// `body`'s north pole and prime meridian at `time`.
    ///
    /// - Throws: `AstronomyError.invalidBody` for a body the reports do not
    ///   cover, before anything else, and `AstronomyError.badTime` when a
    ///   result is not finite. The time is not checked against
    ///   ``Engine/acceptedTTDays``, as the C function does not check it.
    static func axis(of body: CelestialBody, at time: Engine.Time) throws -> Engine.Axis {
        guard bodies.contains(body) else { throw AstronomyError.invalidBody }
        let axis: Engine.Axis
        if body == .earth {
            axis = try earth(at: time)
        } else {
            let tdb = time.tt + Engine.TDB.offsetSeconds(tt: time.tt) / Engine.secondsPerDay
            let (ra, dec, spin) = try elements(of: body, tdb: tdb)
            let north = Engine.Vector<Engine.EQJ>(
                Engine.Spherical(latitude: dec, longitude: ra, distance: 1), time: time)
            axis = Engine.Axis(rightAscension: ra / 15, declination: dec, spin: spin, north: north)
        }
        guard axis.rightAscension.isFinite, axis.declination.isFinite, axis.spin.isFinite,
            axis.north.x.isFinite, axis.north.y.isFinite, axis.north.z.isFinite
        else { throw AstronomyError.badTime }
        return axis
    }

    /// Earth's true pole of date, rotated to J2000, with its right ascension
    /// from 0 up to 24 hours as `Engine.Equatorial` gives it, and its W at
    /// `time.ut`.
    private static func earth(at time: Engine.Time) throws -> Engine.Axis {
        let z = Engine.Vector<Engine.EQD>(x: 0, y: 0, z: 1, time: time)
        let pole = Engine.FrameRotation.eqdToEqj(time).apply(to: z)
        let equatorial = try Engine.Equatorial(pole)
        return Engine.Axis(
            rightAscension: equatorial.rightAscension, declination: equatorial.declination,
            spin: earthSpinAtJ2000 + earthSpinRate * time.ut, north: pole)
    }

    /// The pole's right ascension α0 and declination δ0 and the prime
    /// meridian's W, all in degrees, at `tdb` days of TDB from J2000.
    ///
    /// - Throws: `AstronomyError.invalidBody` for Earth, which
    ///   ``axis(of:at:)`` takes from the C engine's model, and for a body the
    ///   reports do not cover.
    static func elements(of body: CelestialBody, tdb d: Double) throws -> (ra: Double, dec: Double, spin: Double) {
        let t = d / 36_525
        func sine(_ degrees: Double) -> Double { sin(degrees * Engine.radiansPerDegree) }
        func cosine(_ degrees: Double) -> Double { cos(degrees * Engine.radiansPerDegree) }
        switch body {
        case .sun:
            return (286.13, 63.87, 84.176 + 14.1844 * d)
        case .mercury:
            let w =
                329.5988 + 6.1385108 * d
                + 0.01067257 * sine(174.7910857 + 4.092335 * d)
                - 0.00112309 * sine(349.5821714 + 8.184670 * d)
                - 0.00011040 * sine(164.3732571 + 12.277005 * d)
                - 0.00002539 * sine(339.1643429 + 16.369340 * d)
                - 0.00000571 * sine(153.9554286 + 20.461675 * d)
            return (281.0103 - 0.0328 * t, 61.4155 - 0.0049 * t, w)
        case .venus:
            return (272.76, 67.16, 160.20 - 1.4813688 * d)
        case .moon:
            // The 2009 report's Table 2.
            let e1 = 125.045 - 0.0529921 * d
            let e2 = 250.089 - 0.1059842 * d
            let e3 = 260.008 + 13.0120009 * d
            let e4 = 176.625 + 13.3407154 * d
            let e5 = 357.529 + 0.9856003 * d
            let e6 = 311.589 + 26.4057084 * d
            let e7 = 134.963 + 13.0649930 * d
            let e8 = 276.617 + 0.3287146 * d
            let e9 = 34.226 + 1.7484877 * d
            let e10 = 15.134 - 0.1589763 * d
            let e11 = 119.743 + 0.0036096 * d
            let e12 = 239.961 + 0.1643573 * d
            let e13 = 25.053 + 12.9590088 * d
            let (s1, s2, s3, s4) = (sine(e1), sine(e2), sine(e3), sine(e4))
            let (s6, s7, s10, s13) = (sine(e6), sine(e7), sine(e10), sine(e13))
            let ra =
                269.9949 + 0.0031 * t
                - 3.8787 * s1 - 0.1204 * s2 + 0.0700 * s3 - 0.0172 * s4
                + 0.0072 * s6 - 0.0052 * s10 + 0.0043 * s13
            let dec =
                66.5392 + 0.0130 * t
                + 1.5419 * cosine(e1) + 0.0239 * cosine(e2) - 0.0278 * cosine(e3) + 0.0068 * cosine(e4)
                - 0.0029 * cosine(e6) + 0.0009 * cosine(e7) + 0.0008 * cosine(e10) - 0.0009 * cosine(e13)
            let w =
                38.3213 + (13.17635815 - 1.4e-12 * d) * d
                + 3.5610 * s1 + 0.1208 * s2 - 0.0642 * s3 + 0.0158 * s4
                + 0.0252 * sine(e5) - 0.0066 * s6 - 0.0047 * s7 - 0.0046 * sine(e8)
                + 0.0028 * sine(e9) + 0.0052 * s10 + 0.0040 * sine(e11) + 0.0019 * sine(e12)
                - 0.0044 * s13
            return (ra, dec, w)
        case .mars:
            let ra =
                317.269202 - 0.10927547 * t
                + 0.000068 * sine(198.991226 + 19139.4819985 * t)
                + 0.000238 * sine(226.292679 + 38280.8511281 * t)
                + 0.000052 * sine(249.663391 + 57420.7251593 * t)
                + 0.000009 * sine(266.183510 + 76560.6367950 * t)
                + 0.419057 * sine(79.398797 + 0.5042615 * t)
            let dec =
                54.432516 - 0.05827105 * t
                + 0.000051 * cosine(122.433576 + 19139.9407476 * t)
                + 0.000141 * cosine(43.058401 + 38280.8753272 * t)
                + 0.000031 * cosine(57.663379 + 57420.7517205 * t)
                + 0.000005 * cosine(79.476401 + 76560.6495004 * t)
                + 1.591274 * cosine(166.325722 + 0.5042615 * t)
            let w =
                176.049863 + 350.891982443297 * d
                + 0.000145 * sine(129.071773 + 19140.0328244 * t)
                + 0.000157 * sine(36.352167 + 38281.0473591 * t)
                + 0.000040 * sine(56.668646 + 57420.9295360 * t)
                + 0.000001 * sine(67.364003 + 76560.2552215 * t)
                + 0.000001 * sine(104.792680 + 95700.4387578 * t)
                + 0.584542 * sine(95.391654 + 0.5042615 * t)
            return (ra, dec, w)
        case .jupiter:
            let ja = 99.360714 + 4850.4046 * t
            let jb = 175.895369 + 1191.9605 * t
            let jc = 300.323162 + 262.5475 * t
            let jd = 114.012305 + 6070.2476 * t
            let je = 49.511251 + 64.3000 * t
            let ra =
                268.056595 - 0.006499 * t
                + 0.000117 * sine(ja) + 0.000938 * sine(jb) + 0.001432 * sine(jc) + 0.000030 * sine(jd)
                + 0.002150 * sine(je)
            let dec =
                64.495303 + 0.002413 * t
                + 0.000050 * cosine(ja) + 0.000404 * cosine(jb) + 0.000617 * cosine(jc) - 0.000013 * cosine(jd)
                + 0.000926 * cosine(je)
            return (ra, dec, 284.95 + 870.536 * d)
        case .saturn:
            return (40.589 - 0.036 * t, 83.537 - 0.004 * t, 38.90 + 810.7939024 * d)
        case .uranus:
            return (257.311, -15.175, 203.81 - 501.1600928 * d)
        case .neptune:
            let n = 357.85 + 52.316 * t
            let sn = sine(n)
            return (299.36 + 0.70 * sn, 43.46 - 0.51 * cosine(n), 249.978 + 541.1397757 * d - 0.48 * sn)
        case .pluto:
            return (132.993, -6.163, 302.695 + 56.3625225 * d)
        default:
            throw AstronomyError.invalidBody
        }
    }
}

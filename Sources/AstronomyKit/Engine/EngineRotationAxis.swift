//
//  EngineRotationAxis.swift
//  AstronomyKit
//
//  Pure-Swift planetary rotation axis orientation (IAU WGCCRE 2015) matching Astronomy_RotationAxis.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

enum EngineRotationAxis {
    static func rotationAxis(of body: CelestialBody, at time: AstroTime) throws -> RotationAxis {
        let deg2Rad = EngineConstants.deg2Rad
        let d = time.terrestrialTime
        let centuries = d / 36525.0

        let ra: Double
        let dec: Double
        let spin: Double

        switch body {
        case .sun:
            ra = 286.13
            dec = 63.87
            spin = 84.176 + 14.1844 * d

        case .mercury:
            ra = 281.0103 - 0.0328 * centuries
            dec = 61.4155 - 0.0049 * centuries
            spin =
                329.5988
                + 6.1385108 * d
                + 0.01067257 * sin(deg2Rad * (174.7910857 + 4.092335 * d))
                - 0.00112309 * sin(deg2Rad * (349.5821714 + 8.184670 * d))
                - 0.00011040 * sin(deg2Rad * (164.3732571 + 12.277005 * d))
                - 0.00002539 * sin(deg2Rad * (339.1643429 + 16.369340 * d))
                - 0.00000571 * sin(deg2Rad * (153.9554286 + 20.461675 * d))

        case .venus:
            ra = 272.76
            dec = 67.16
            spin = 160.20 - 1.4813688 * d

        case .earth:
            return try earthRotationAxis(at: time)

        case .moon:
            let e1 = deg2Rad * (125.045 - 0.0529921 * d)
            let e2 = deg2Rad * (250.089 - 0.1059842 * d)
            let e3 = deg2Rad * (260.008 + 13.0120009 * d)
            let e4 = deg2Rad * (176.625 + 13.3407154 * d)
            let e5 = deg2Rad * (357.529 + 0.9856003 * d)
            let e6 = deg2Rad * (311.589 + 26.4057084 * d)
            let e7 = deg2Rad * (134.963 + 13.0649930 * d)
            let e8 = deg2Rad * (276.617 + 0.3287146 * d)
            let e9 = deg2Rad * (34.226 + 1.7484877 * d)
            let e10 = deg2Rad * (15.134 - 0.1589763 * d)
            let e11 = deg2Rad * (119.743 + 0.0036096 * d)
            let e12 = deg2Rad * (239.961 + 0.1643573 * d)
            let e13 = deg2Rad * (25.053 + 12.9590088 * d)

            ra =
                269.9949 + 0.0031 * centuries
                - 3.8787 * sin(e1)
                - 0.1204 * sin(e2)
                + 0.0700 * sin(e3)
                - 0.0172 * sin(e4)
                + 0.0072 * sin(e6)
                - 0.0052 * sin(e10)
                + 0.0043 * sin(e13)

            dec =
                66.5392 + 0.0130 * centuries
                + 1.5419 * cos(e1)
                + 0.0239 * cos(e2)
                - 0.0278 * cos(e3)
                + 0.0068 * cos(e4)
                - 0.0029 * cos(e6)
                + 0.0009 * cos(e7)
                + 0.0008 * cos(e10)
                - 0.0009 * cos(e13)

            spin =
                38.3213 + (13.17635815 - 1.4e-12 * d) * d
                + 3.5610 * sin(e1)
                + 0.1208 * sin(e2)
                - 0.0642 * sin(e3)
                + 0.0158 * sin(e4)
                + 0.0252 * sin(e5)
                - 0.0066 * sin(e6)
                - 0.0047 * sin(e7)
                - 0.0046 * sin(e8)
                + 0.0028 * sin(e9)
                + 0.0052 * sin(e10)
                + 0.0040 * sin(e11)
                + 0.0019 * sin(e12)
                - 0.0044 * sin(e13)

        case .mars:
            ra =
                317.269202 - 0.10927547 * centuries
                + 0.000068 * sin(deg2Rad * (198.991226 + 19139.4819985 * centuries))
                + 0.000238 * sin(deg2Rad * (226.292679 + 38280.8511281 * centuries))
                + 0.000052 * sin(deg2Rad * (249.663391 + 57420.7251593 * centuries))
                + 0.000009 * sin(deg2Rad * (266.183510 + 76560.6367950 * centuries))
                + 0.419057 * sin(deg2Rad * (79.398797 + 0.5042615 * centuries))

            dec =
                54.432516 - 0.05827105 * centuries
                + 0.000051 * cos(deg2Rad * (122.433576 + 19139.9407476 * centuries))
                + 0.000141 * cos(deg2Rad * (43.058401 + 38280.8753272 * centuries))
                + 0.000031 * cos(deg2Rad * (57.663379 + 57420.7517205 * centuries))
                + 0.000005 * cos(deg2Rad * (79.476401 + 76560.6495004 * centuries))
                + 1.591274 * cos(deg2Rad * (166.325722 + 0.5042615 * centuries))

            spin =
                176.049863 + 350.891982443297 * d
                + 0.000145 * sin(deg2Rad * (129.071773 + 19140.0328244 * centuries))
                + 0.000157 * sin(deg2Rad * (36.352167 + 38281.0473591 * centuries))
                + 0.000040 * sin(deg2Rad * (56.668646 + 57420.9295360 * centuries))
                + 0.000001 * sin(deg2Rad * (67.364003 + 76560.2552215 * centuries))
                + 0.000001 * sin(deg2Rad * (104.792680 + 95700.4387578 * centuries))
                + 0.584542 * sin(deg2Rad * (95.391654 + 0.5042615 * centuries))

        case .jupiter:
            let ja = deg2Rad * (99.360714 + 4850.4046 * centuries)
            let jb = deg2Rad * (175.895369 + 1191.9605 * centuries)
            let jc = deg2Rad * (300.323162 + 262.5475 * centuries)
            let jd = deg2Rad * (114.012305 + 6070.2476 * centuries)
            let je = deg2Rad * (49.511251 + 64.3000 * centuries)

            ra =
                268.056595 - 0.006499 * centuries
                + 0.000117 * sin(ja)
                + 0.000938 * sin(jb)
                + 0.001432 * sin(jc)
                + 0.000030 * sin(jd)
                + 0.002150 * sin(je)

            dec =
                64.495303 + 0.002413 * centuries
                + 0.000050 * cos(ja)
                + 0.000404 * cos(jb)
                + 0.000617 * cos(jc)
                - 0.000013 * cos(jd)
                + 0.000926 * cos(je)

            spin = 284.95 + 870.536 * d

        case .saturn:
            ra = 40.589 - 0.036 * centuries
            dec = 83.537 - 0.004 * centuries
            spin = 38.90 + 810.7939024 * d

        case .uranus:
            ra = 257.311
            dec = -15.175
            spin = 203.81 - 501.1600928 * d

        case .neptune:
            let n = deg2Rad * (357.85 + 52.316 * centuries)
            ra = 299.36 + 0.70 * sin(n)
            dec = 43.46 - 0.51 * cos(n)
            spin = 249.978 + 541.1397757 * d - 0.48 * sin(n)

        case .pluto:
            ra = 132.993
            dec = -6.163
            spin = 302.695 + 56.3625225 * d

        default:
            throw AstronomyError.invalidBody
        }

        let radLat = dec * deg2Rad
        let radLon = ra * deg2Rad
        let rCosLat = cos(radLat)
        let north = Vector3D(
            x: rCosLat * cos(radLon),
            y: rCosLat * sin(radLon),
            z: sin(radLat),
            time: time
        )

        return RotationAxis(
            rightAscension: ra / 15.0,
            declination: dec,
            spin: spin,
            north: north
        )
    }

    private static func earthRotationAxis(at time: AstroTime) throws -> RotationAxis {
        let rot = EngineRotation.eqdToEqj(at: time)
        // Rotating EQD north pole (0, 0, 1) to J2000 selects row 2 of the rotation matrix.
        let (nx, ny, nz) = EngineMath.rotate(rot, 0.0, 0.0, 1.0)
        let equ = try EngineMath.equatorFromVector(nx, ny, nz)
        let north = Vector3D(x: nx, y: ny, z: nz, time: time)
        let spin = 190.41375788700253 + 360.9856122880876 * time.universalTime
        return RotationAxis(
            rightAscension: equ.ra,
            declination: equ.dec,
            spin: spin,
            north: north
        )
    }
}

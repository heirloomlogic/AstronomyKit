//
//  EngineMoonCore.swift
//  AstronomyKit
//
//  Pure-Swift analytical lunar position (Brown / Montenbruck-Pfleger)
//  matching CalcMoon in astronomy.c.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct EngineMoonPosition {
    let lon: Double
    let lat: Double
    let distanceAU: Double
}

private struct MoonSolRow {
    let cl: Double
    let cs: Double
    let cg: Double
    let cp: Double
    let idxP: UInt8
    let idxQ: UInt8
    let idxR: UInt8
    let idxS: UInt8
}

private struct MoonNRow {
    let cn: Double
    let idxP: UInt8
    let idxQ: UInt8
    let idxR: UInt8
    let idxS: UInt8
}

private struct MoonTableStorage: @unchecked Sendable {
    let sol: UnsafePointer<MoonSolRow>
    let solCount: Int
    let solarN: UnsafePointer<MoonNRow>
    let nCount: Int

    static let shared: MoonTableStorage = build()

    private static func build() -> MoonTableStorage {
        let solCoeffs: [Double] = [
            13.9020, 14.0600, -0.0010, 0.2607,
            0.4030, -4.0100, 0.3940, 0.0023,
            2369.9120, 2373.3600, 0.6010, 28.2333,
            -125.1540, -112.7900, -0.7250, -0.9781,
            1.9790, 6.9800, -0.4450, 0.0433,
            191.9530, 192.7200, 0.0290, 3.0861,
            -8.4660, -13.5100, 0.4550, -0.1093,
            22639.5000, 22609.0700, 0.0790, 186.5398,
            18.6090, 3.5900, -0.0940, 0.0118,
            -4586.4650, -4578.1300, -0.0770, 34.3117,
            3.2150, 5.4400, 0.1920, -0.0386,
            -38.4280, -38.6400, 0.0010, 0.6008,
            -0.3930, -1.4300, -0.0920, 0.0086,
            -0.2890, -1.5900, 0.1230, -0.0053,
            -24.4200, -25.1000, 0.0400, -0.3000,
            18.0230, 17.9300, 0.0070, 0.1494,
            -668.1460, -126.9800, -1.3020, -0.3997,
            0.5600, 0.3200, -0.0010, -0.0037,
            -165.1450, -165.0600, 0.0540, 1.9178,
            -1.8770, -6.4600, -0.4160, 0.0339,
            0.2130, 1.0200, -0.0740, 0.0054,
            14.3870, 14.7800, -0.0170, 0.2833,
            -0.5860, -1.2000, 0.0540, -0.0100,
            769.0160, 767.9600, 0.1070, 10.1657,
            1.7500, 2.0100, -0.0180, 0.0155,
            -211.6560, -152.5300, 5.6790, -0.3039,
            1.2250, 0.9100, -0.0300, -0.0088,
            -30.7730, -34.0700, -0.3080, 0.3722,
            -0.5700, -1.4000, -0.0740, 0.0109,
            -2.9210, -11.7500, 0.7870, -0.0484,
            1.2670, 1.5200, -0.0220, 0.0164,
            -109.6730, -115.1800, 0.4610, -0.9490,
            -205.9620, -182.3600, 2.0560, 1.4437,
            0.2330, 0.3600, 0.0120, -0.0025,
            -4.3910, -9.6600, -0.4710, 0.0673,
            0.2830, 1.5300, -0.1110, 0.0060,
            14.5770, 31.7000, -1.5400, 0.2302,
            147.6870, 138.7600, 0.6790, 1.1528,
            -1.0890, 0.5500, 0.0210, 0.0000,
            28.4750, 23.5900, -0.4430, -0.2257,
            -0.2760, -0.3800, -0.0060, -0.0036,
            0.6360, 2.2700, 0.1460, -0.0102,
            -0.1890, -1.6800, 0.1310, -0.0028,
            -7.4860, -0.6600, -0.0370, -0.0086,
            -8.0960, -16.3500, -0.7400, 0.0918,
            -5.7410, -0.0400, 0.0000, -0.0009,
            0.2550, 0.0000, 0.0000, 0.0000,
            -411.6080, -0.2000, 0.0000, -0.0124,
            0.5840, 0.8400, 0.0000, 0.0071,
            -55.1730, -52.1400, 0.0000, -0.1052,
            0.2540, 0.2500, 0.0000, -0.0017,
            0.0250, -1.6700, 0.0000, 0.0031,
            1.0600, 2.9600, -0.1660, 0.0243,
            36.1240, 50.6400, -1.3000, 0.6215,
            -13.1930, -16.4000, 0.2580, -0.1187,
            -1.1870, -0.7400, 0.0420, 0.0074,
            -0.2930, -0.3100, -0.0020, 0.0046,
            -0.2900, -1.4500, 0.1160, -0.0051,
            -7.6490, -10.5600, 0.2590, -0.1038,
            -8.6270, -7.5900, 0.0780, -0.0192,
            -2.7400, -2.5400, 0.0220, 0.0324,
            1.1810, 3.3200, -0.2120, 0.0213,
            9.7030, 11.6700, -0.1510, 0.1268,
            -0.3520, -0.3700, 0.0010, -0.0028,
            -2.4940, -1.1700, -0.0030, -0.0017,
            0.3600, 0.2000, -0.0120, -0.0043,
            -1.1670, -1.2500, 0.0080, -0.0106,
            -7.4120, -6.1200, 0.1170, 0.0484,
            -0.3110, -0.6500, -0.0320, 0.0044,
            0.7570, 1.8200, -0.1050, 0.0112,
            2.5800, 2.3200, 0.0270, 0.0196,
            2.5330, 2.4000, -0.0140, -0.0212,
            -0.3440, -0.5700, -0.0250, 0.0036,
            -0.9920, -0.0200, 0.0000, 0.0000,
            -45.0990, -0.0200, 0.0000, -0.0010,
            -0.1790, -9.5200, 0.0000, -0.0833,
            -0.3010, -0.3300, 0.0000, 0.0014,
            -6.3820, -3.3700, 0.0000, -0.0481,
            39.5280, 85.1300, 0.0000, -0.7136,
            9.3660, 0.7100, 0.0000, -0.0112,
            0.2020, 0.0200, 0.0000, 0.0000,
            0.4150, 0.1000, 0.0000, 0.0013,
            -2.1520, -2.2600, 0.0000, -0.0066,
            -1.4400, -1.3000, 0.0000, 0.0014,
            0.3840, -0.0400, 0.0000, 0.0000,
            1.9380, 3.6000, -0.1450, 0.0401,
            -0.9520, -1.5800, 0.0520, -0.0130,
            -0.5510, -0.9400, 0.0320, -0.0097,
            -0.4820, -0.5700, 0.0050, -0.0045,
            0.6810, 0.9600, -0.0260, 0.0115,
            -0.2970, -0.2700, 0.0020, -0.0009,
            0.2540, 0.2100, -0.0030, 0.0000,
            -0.2500, -0.2200, 0.0040, 0.0014,
            -3.9960, 0.0000, 0.0000, 0.0004,
            0.5570, -0.7500, 0.0000, -0.0090,
            -0.4590, -0.3800, 0.0000, -0.0053,
            -1.2980, 0.7400, 0.0000, 0.0004,
            0.5380, 1.1400, 0.0000, -0.0141,
            0.2630, 0.0200, 0.0000, 0.0000,
            0.4260, 0.0700, 0.0000, -0.0006,
            -0.3040, 0.0300, 0.0000, 0.0003,
            -0.3720, -0.1900, 0.0000, -0.0027,
            0.4180, 0.0000, 0.0000, 0.0000,
            -0.3300, -0.0400, 0.0000, 0.0000,
        ]
        let solIdx: [UInt8] = [
            6, 19, 32, 49,
            6, 19, 32, 48,
            6, 19, 32, 47,
            6, 19, 32, 46,
            7, 19, 32, 49,
            7, 19, 32, 47,
            7, 19, 32, 46,
            7, 19, 32, 45,
            7, 19, 32, 44,
            7, 19, 32, 43,
            7, 19, 32, 42,
            7, 19, 32, 41,
            7, 19, 32, 39,
            6, 20, 32, 49,
            6, 20, 32, 47,
            6, 20, 32, 46,
            6, 20, 32, 45,
            6, 20, 32, 44,
            6, 20, 32, 43,
            6, 20, 32, 41,
            8, 19, 32, 49,
            8, 19, 32, 47,
            8, 19, 32, 46,
            8, 19, 32, 45,
            8, 19, 32, 44,
            8, 19, 32, 43,
            8, 19, 32, 42,
            8, 19, 32, 41,
            8, 19, 32, 39,
            7, 20, 32, 47,
            7, 20, 32, 46,
            7, 20, 32, 45,
            7, 20, 32, 43,
            7, 20, 32, 42,
            7, 20, 32, 41,
            7, 18, 32, 49,
            7, 18, 32, 47,
            7, 18, 32, 45,
            7, 18, 32, 44,
            7, 18, 32, 43,
            7, 18, 32, 42,
            7, 18, 32, 41,
            6, 21, 32, 47,
            6, 21, 32, 45,
            6, 21, 32, 43,
            6, 19, 34, 47,
            6, 19, 34, 46,
            6, 19, 34, 45,
            6, 19, 34, 44,
            6, 19, 34, 43,
            6, 19, 34, 42,
            6, 19, 34, 41,
            9, 19, 32, 47,
            9, 19, 32, 45,
            9, 19, 32, 43,
            9, 19, 32, 41,
            9, 19, 32, 39,
            8, 20, 32, 47,
            8, 20, 32, 45,
            8, 20, 32, 43,
            8, 20, 32, 41,
            8, 18, 32, 47,
            8, 18, 32, 45,
            8, 18, 32, 44,
            8, 18, 32, 43,
            8, 18, 32, 41,
            7, 21, 32, 45,
            7, 21, 32, 43,
            7, 21, 32, 41,
            7, 17, 32, 47,
            7, 17, 32, 45,
            7, 17, 32, 43,
            6, 22, 32, 43,
            7, 19, 34, 47,
            7, 19, 34, 45,
            7, 19, 34, 43,
            7, 19, 34, 41,
            7, 19, 30, 47,
            7, 19, 30, 45,
            7, 19, 30, 43,
            7, 19, 30, 41,
            6, 20, 34, 45,
            6, 20, 34, 43,
            6, 20, 30, 47,
            6, 20, 30, 43,
            10, 19, 32, 45,
            10, 19, 32, 43,
            9, 20, 32, 45,
            9, 20, 32, 43,
            9, 18, 32, 45,
            8, 21, 32, 43,
            8, 17, 32, 43,
            7, 22, 32, 43,
            8, 19, 34, 45,
            8, 19, 34, 43,
            8, 19, 30, 47,
            8, 19, 30, 45,
            8, 19, 30, 43,
            7, 20, 34, 45,
            7, 20, 30, 43,
            7, 18, 34, 45,
            7, 18, 30, 47,
            6, 19, 36, 45,
            9, 19, 34, 45,
        ]
        let solCount = solCoeffs.count / 4
        let solBuf = UnsafeMutablePointer<MoonSolRow>.allocate(capacity: solCount)
        var i = 0
        while i < solCount {
            let b = i &* 4
            solBuf[i] = MoonSolRow(
                cl: solCoeffs[b],
                cs: solCoeffs[b &+ 1],
                cg: solCoeffs[b &+ 2],
                cp: solCoeffs[b &+ 3],
                idxP: solIdx[b],
                idxQ: solIdx[b &+ 1],
                idxR: solIdx[b &+ 2],
                idxS: solIdx[b &+ 3]
            )
            i &+= 1
        }

        let nCoeffs: [Double] = [
            -526.069,
            -3.352,
            +44.297,
            -6.000,
            +20.599,
            -30.598,
            -24.649,
            -2.000,
            -22.571,
            +10.985,
        ]
        let nIdx: [UInt8] = [
            6, 19, 33, 43,
            6, 19, 33, 41,
            7, 19, 33, 43,
            7, 19, 33, 41,
            5, 19, 33, 45,
            5, 19, 33, 43,
            4, 19, 33, 45,
            4, 19, 33, 43,
            6, 20, 33, 43,
            6, 18, 33, 43,
        ]
        let nCount = nCoeffs.count
        let nBuf = UnsafeMutablePointer<MoonNRow>.allocate(capacity: nCount)
        i = 0
        while i < nCount {
            let b = i &* 4
            nBuf[i] = MoonNRow(
                cn: nCoeffs[i],
                idxP: nIdx[b],
                idxQ: nIdx[b &+ 1],
                idxR: nIdx[b &+ 2],
                idxS: nIdx[b &+ 3]
            )
            i &+= 1
        }
        return MoonTableStorage(
            sol: UnsafePointer(solBuf),
            solCount: solCount,
            solarN: UnsafePointer(nBuf),
            nCount: nCount
        )
    }
}

enum EngineMoonCore {
    @inline(__always)
    private static func frac(_ x: Double) -> Double {
        x - floor(x)
    }

    @inline(__always)
    private static func sine(_ phi: Double) -> Double {
        sin(EngineConstants.pi2 * phi)
    }

    static func calcMoon(centuries t: Double) -> EngineMoonPosition {
        let table = MoonTableStorage.shared
        let pi2 = EngineConstants.pi2
        let arc = EngineConstants.arc
        let t2 = t * t

        let s1 = sine(0.19833 + 0.05611 * t)
        let s2 = sine(0.27869 + 0.04508 * t)
        let s3 = sine(0.16827 - 0.36903 * t)
        let s4 = sine(0.34734 - 5.37261 * t)
        let s5 = sine(0.10498 - 5.37899 * t)
        let s6 = sine(0.42681 - 0.41855 * t)
        let s7 = sine(0.14943 - 5.37511 * t)

        let dl0 = 0.84 * s1 + 0.31 * s2 + 14.27 * s3 + 7.26 * s4 + 0.28 * s5 + 0.24 * s6
        let dl = 2.94 * s1 + 0.31 * s2 + 14.27 * s3 + 9.34 * s4 + 1.12 * s5 + 0.83 * s6
        let dls = -6.40 * s1 - 1.89 * s6
        let df = 0.21 * s1 + 0.31 * s2 + 14.27 * s3 - 88.70 * s4 - 15.30 * s5 + 0.24 * s6 - 1.86 * s7
        let dd = dl0 - dls
        let dgam =
            -3332e-9 * sine(0.59734 - 5.37261 * t)
            - 539e-9 * sine(0.35498 - 5.37899 * t)
            - 64e-9 * sine(0.39943 - 5.37511 * t)

        let l0 = pi2 * frac(0.60643382 + 1336.85522467 * t - 0.00000313 * t2) + dl0 / arc
        let l = pi2 * frac(0.37489701 + 1325.55240982 * t + 0.00002565 * t2) + dl / arc
        let ls = pi2 * frac(0.99312619 + 99.99735956 * t - 0.00000044 * t2) + dls / arc
        let f = pi2 * frac(0.25909118 + 1342.22782980 * t - 0.00000892 * t2) + df / arc
        let d = pi2 * frac(0.82736186 + 1236.85308708 * t - 0.00000397 * t2) + dd / arc

        return withUnsafeTemporaryAllocation(of: Double.self, capacity: 104) { buf in
            guard let co = buf.baseAddress else {
                preconditionFailure("Temporary allocation failed")
            }
            let si = co + 52

            @inline(__always)
            func fillRow(base: Int, arg: Double, maxJ: Int, fac: Double) {
                co[base &+ 6] = 1.0
                si[base &+ 6] = 0.0
                let c1 = cos(arg) * fac
                let s1 = sin(arg) * fac
                co[base &+ 7] = c1
                si[base &+ 7] = s1
                co[base &+ 5] = c1
                si[base &+ 5] = -s1
                var pc = c1
                var ps = s1
                var j = 2
                while j <= maxJ {
                    let nc = pc * c1 - ps * s1
                    let ns = ps * c1 + pc * s1
                    co[base &+ 6 &+ j] = nc
                    si[base &+ 6 &+ j] = ns
                    co[base &+ 6 &- j] = nc
                    si[base &+ 6 &- j] = -ns
                    pc = nc
                    ps = ns
                    j &+= 1
                }
            }

            fillRow(base: 0, arg: l, maxJ: 4, fac: 1.000002208)
            fillRow(base: 13, arg: ls, maxJ: 3, fac: 0.997504612 - 0.002495388 * t)
            fillRow(base: 26, arg: f, maxJ: 4, fac: 1.000002708 + 139.978 * dgam)
            fillRow(base: 39, arg: d, maxJ: 6, fac: 1.0)

            var dlam = 0.0
            var ds = 0.0
            var gam1c = 0.0
            var sinpi = 3422.7000

            let sol = table.sol
            let solCount = table.solCount
            var i = 0
            while i < solCount {
                let row = sol[i]
                let ip = Int(row.idxP)
                let iq = Int(row.idxQ)
                let ir = Int(row.idxR)
                let isIdx = Int(row.idxS)
                let cp = co[ip]
                let sp = si[ip]
                let cq = co[iq]
                let sq = si[iq]
                let c1 = cp * cq - sp * sq
                let s1 = sp * cq + cp * sq
                let cr = co[ir]
                let sr = si[ir]
                let c2 = c1 * cr - s1 * sr
                let s2 = s1 * cr + c1 * sr
                let cs = co[isIdx]
                let ss = si[isIdx]
                let x = c2 * cs - s2 * ss
                let y = s2 * cs + c2 * ss
                dlam += row.cl * y
                ds += row.cs * y
                gam1c += row.cg * x
                sinpi += row.cp * x
                i &+= 1
            }

            var nSum = 0.0
            let solarN = table.solarN
            let nCount = table.nCount
            i = 0
            while i < nCount {
                let row = solarN[i]
                let ip = Int(row.idxP)
                let iq = Int(row.idxQ)
                let ir = Int(row.idxR)
                let isIdx = Int(row.idxS)
                let cp = co[ip]
                let sp = si[ip]
                let cq = co[iq]
                let sq = si[iq]
                let c1 = cp * cq - sp * sq
                let s1 = sp * cq + cp * sq
                let cr = co[ir]
                let sr = si[ir]
                let c2 = c1 * cr - s1 * sr
                let s2 = s1 * cr + c1 * sr
                let cs = co[isIdx]
                let ss = si[isIdx]
                let y = s2 * cs + c2 * ss
                nSum += row.cn * y
                i &+= 1
            }

            dlam +=
                0.82 * sine(0.7736 - 62.5512 * t) + 0.31 * sine(0.0466 - 125.1025 * t)
                + 0.35 * sine(0.5785 - 25.1042 * t) + 0.66 * sine(0.4591 + 1335.8075 * t)
                + 0.64 * sine(0.3130 - 91.5680 * t) + 1.14 * sine(0.1480 + 1331.2898 * t)
                + 0.21 * sine(0.5918 + 1056.5859 * t) + 0.44 * sine(0.5784 + 1322.8595 * t)
                + 0.24 * sine(0.2275 - 5.7374 * t) + 0.28 * sine(0.2965 + 2.6929 * t)
                + 0.33 * sine(0.3132 + 6.3368 * t)

            let sArg = f + ds / arc
            let latSeconds =
                (1.000002708 + 139.978 * dgam) * (18518.511 + 1.189 + gam1c) * sin(sArg)
                - 6.24 * sin(3.0 * sArg) + nSum

            let geoLon = pi2 * frac((l0 + dlam / arc) / pi2)
            let geoLat = latSeconds * (EngineConstants.deg2Rad / 3600.0)
            let distAU = (arc * EngineConstants.earthEquatorialRadiusAU) / (0.999953253 * sinpi)
            return EngineMoonPosition(lon: geoLon, lat: geoLat, distanceAU: distAU)
        }
    }
}

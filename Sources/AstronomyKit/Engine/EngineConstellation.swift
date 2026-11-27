//
//  EngineConstellation.swift
//  AstronomyKit
//
//  Pure-Swift IAU constellation lookup (B1875 boundaries) matching Astronomy_Constellation.
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

private struct ConstelBoundary {
    let raLo: Double
    let raHi: Double
    let decLo: Double
    let index: UInt8
}

private struct ConstelTableStorage: @unchecked Sendable {
    let bounds: UnsafePointer<ConstelBoundary>
    let count: Int
    let info: UnsafePointer<(symbol: String, name: String)>
    let infoCount: Int
    let r00: Double
    let r01: Double
    let r02: Double
    let r10: Double
    let r11: Double
    let r12: Double
    let r20: Double
    let r21: Double
    let r22: Double

    static let shared: ConstelTableStorage = build()

    private static func build() -> ConstelTableStorage {
        let coords: [Double] = [
            0, 8640, 2112,
            2880, 5220, 2076,
            7560, 8280, 2068,
            6480, 7560, 2064,
            0, 2880, 2040,
            3300, 3840, 1968,
            0, 1800, 1920,
            3840, 5220, 1920,
            6300, 6480, 1920,
            7260, 7560, 1920,
            0, 1263, 1848,
            4140, 4890, 1848,
            5952, 6300, 1800,
            7260, 7440, 1800,
            2868, 3300, 1764,
            3300, 4080, 1764,
            4680, 5952, 1680,
            1116, 1230, 1632,
            7350, 7440, 1608,
            4080, 4320, 1596,
            0, 120, 1584,
            5040, 5640, 1584,
            8490, 8640, 1584,
            4320, 4860, 1536,
            4860, 5190, 1512,
            8340, 8490, 1512,
            2196, 2520, 1488,
            7200, 7350, 1476,
            7393.2, 7416, 1462,
            2520, 2868, 1440,
            2868, 3030, 1440,
            7116, 7200, 1428,
            7200, 7393.2, 1428,
            8232, 8340, 1418,
            0, 876, 1404,
            6990, 7116, 1392,
            612, 687, 1380,
            876, 1116, 1368,
            1116, 1140, 1368,
            8034, 8232, 1350,
            1800, 2196, 1344,
            5052, 5190, 1332,
            5190, 6990, 1332,
            1140, 1200, 1320,
            7968, 8034, 1320,
            7416, 7908, 1316,
            0, 612, 1296,
            2196, 2340, 1296,
            4350, 4860, 1272,
            5490, 5670, 1272,
            7908, 7968, 1266,
            1200, 1800, 1260,
            8232, 8400, 1260,
            5670, 6120, 1236,
            735, 906, 1212,
            6120, 6564, 1212,
            0, 492, 1200,
            492, 600, 1200,
            2340, 2448, 1200,
            8400, 8640, 1200,
            4860, 5052, 1164,
            0, 402, 1152,
            8490, 8640, 1152,
            6543, 6564, 1140,
            6564, 6870, 1140,
            6870, 6900, 1140,
            600, 735, 1128,
            3030, 3300, 1128,
            60, 312, 1104,
            4320, 4350, 1080,
            2448, 2652, 1068,
            7887, 7908, 1056,
            7875, 7887, 1050,
            6900, 6984, 1044,
            3300, 3660, 1008,
            3660, 3882, 960,
            5556, 5670, 960,
            5670, 5880, 960,
            3330, 3450, 954,
            0, 906, 882,
            906, 924, 882,
            6969, 6984, 876,
            1620, 1689, 864,
            7824, 7875, 864,
            7875, 7920, 864,
            2352, 2652, 852,
            2652, 2790, 852,
            0, 720, 840,
            7920, 8214, 840,
            8214, 8232, 828,
            8232, 8460, 828,
            924, 978, 816,
            3882, 3960, 816,
            4320, 4440, 816,
            2790, 3330, 804,
            3330, 3558, 804,
            258, 507, 792,
            5466, 5556, 792,
            8460, 8550, 770,
            4440, 4770, 768,
            8550, 8640, 752,
            5025, 5052, 738,
            870, 978, 736,
            978, 1620, 736,
            1620, 1710, 720,
            6543, 6969, 720,
            3960, 4320, 696,
            7080, 7530, 696,
            1710, 2118, 684,
            3558, 3780, 684,
            4770, 5025, 684,
            0, 24, 672,
            507, 600, 672,
            2118, 2352, 672,
            2838, 2880, 672,
            7530, 7824, 672,
            6933, 7080, 660,
            690, 870, 654,
            5820, 5880, 648,
            5430, 5466, 624,
            5466, 5820, 624,
            6612, 6792, 624,
            3870, 3960, 612,
            6792, 6933, 612,
            600, 690, 600,
            258, 306, 570,
            3780, 3870, 564,
            7650, 7710, 564,
            2052, 2118, 548,
            24, 51, 528,
            5730, 5772, 528,
            2118, 2238, 516,
            7140, 7290, 510,
            6792, 6930, 506,
            51, 306, 504,
            7290, 7404, 492,
            2811, 2838, 480,
            7404, 7650, 468,
            6930, 7140, 460,
            1182, 1212, 456,
            6792, 6840, 444,
            2052, 2076, 432,
            2238, 2271, 420,
            6840, 7140, 388,
            1788, 1920, 384,
            5730, 5790, 384,
            7140, 7290, 378,
            1662, 1788, 372,
            1920, 2016, 372,
            4620, 4860, 360,
            6210, 6570, 344,
            4272, 4620, 336,
            2700, 2811, 324,
            6030, 6210, 308,
            0, 51, 300,
            2016, 2076, 300,
            2520, 2700, 300,
            7602, 7680, 300,
            2271, 2496, 288,
            6570, 6792, 288,
            7515, 7578, 284,
            7578, 7602, 284,
            4146, 4272, 264,
            2247, 2271, 240,
            2496, 2520, 240,
            2811, 2853, 240,
            8580, 8640, 240,
            600, 1182, 238,
            7251, 7308, 204,
            4860, 5430, 192,
            8190, 8580, 180,
            2853, 3330, 168,
            3330, 3870, 168,
            6570, 6718.4, 150,
            6718.4, 6792, 150,
            7500, 7515, 144,
            2520, 2526, 132,
            6570, 6633, 108,
            5790, 6030, 96,
            6570, 6633, 72,
            7728, 7800, 66,
            0, 720, 48,
            6690, 6792, 48,
            7308, 7500, 48,
            7500, 7680, 48,
            7680, 7728, 48,
            7920, 8190, 48,
            7800, 7920, 42,
            2526, 2592, 36,
            1290, 1662, 0,
            1662, 1680, 0,
            2592, 2910, 0,
            5280, 5430, 0,
            6420, 6570, 0,
            954, 1182, -42,
            1182, 1290, -42,
            5430, 5856, -78,
            1680, 1830, -96,
            2100, 2247, -96,
            6420, 6468, -96,
            6570, 6690, -96,
            6690, 6792, -96,
            8190, 8580, -96,
            3870, 4146, -144,
            4146, 4260, -144,
            0, 120, -168,
            8580, 8640, -168,
            5130, 5280, -192,
            5730, 5856, -192,
            7200, 7392, -216,
            7680, 7872, -216,
            6180, 6468, -240,
            2100, 2910, -264,
            1770, 1830, -264,
            1830, 2100, -264,
            2910, 3012, -264,
            3450, 3870, -264,
            4260, 4620, -264,
            6330, 6360, -280,
            6792, 7200, -288.8,
            1740, 1770, -348,
            7392, 7680, -360,
            6180, 6570, -384,
            6570, 6792, -384,
            3012, 3090, -408,
            5856, 5895, -438,
            3090, 3270, -456,
            3870, 3900, -456,
            5856, 5895, -462,
            5640, 5730, -480,
            4530, 4620, -528,
            4620, 5130, -528,
            3270, 3510, -576,
            600, 954, -585.2,
            954, 1350, -585.2,
            3900, 4260, -588,
            4260, 4530, -588,
            5130, 5370, -588,
            5856, 6030, -590,
            0, 600, -612,
            7680, 7872, -612,
            7872, 8580, -612,
            8580, 8640, -612,
            3510, 3690, -636,
            1692, 1740, -654,
            1740, 2202, -654,
            7200, 7680, -672,
            3690, 3810, -700,
            4530, 5370, -708,
            5370, 5640, -708,
            5640, 5760, -708,
            1650, 1692, -720,
            6030, 6336, -720,
            6336, 6420, -720,
            3810, 3900, -748,
            2202, 2652, -792,
            4410, 4530, -792,
            3900, 4410, -840,
            1260, 1350, -864,
            3012, 3372, -882,
            1536, 1650, -888,
            6420, 6900, -888,
            7680, 8280, -888,
            8280, 8400, -888,
            1080, 1260, -950,
            3372, 3960, -954,
            0, 600, -960,
            600, 1080, -960,
            1392, 1536, -960,
            8400, 8640, -960,
            5100, 5370, -1008,
            5640, 5760, -1008,
            5760, 5911.5, -1008,
            1740, 1800, -1032,
            1800, 2370, -1032,
            2880, 3012, -1032,
            1230, 1392, -1056,
            5911.5, 6420, -1092,
            6420, 6900, -1092,
            6900, 7320, -1092,
            7320, 7680, -1092,
            1080, 1230, -1104,
            1620, 1740, -1116,
            5520, 5640, -1152,
            0, 840, -1156,
            960, 1080, -1176,
            1470, 1536, -1176,
            1536, 1620, -1176,
            7680, 7920, -1200,
            2160, 2880, -1218,
            2880, 2940, -1218,
            870, 960, -1224,
            1380, 1470, -1224,
            0, 660, -1236,
            2160, 2220, -1260,
            2940, 3042, -1272,
            1260, 1380, -1276,
            1380, 1440, -1276,
            0, 570, -1284,
            780, 870, -1296,
            1620, 1800, -1296,
            5418, 5520, -1296,
            3042, 3180, -1308,
            2220, 2340, -1320,
            4260, 4620, -1320,
            5100, 5418, -1320,
            5418, 5520, -1320,
            1440, 1560, -1356,
            3180, 3960, -1356,
            3960, 4050, -1356,
            6300, 6480, -1368,
            6480, 7320, -1368,
            7920, 8400, -1368,
            1152, 1260, -1380,
            1800, 1980, -1380,
            2340, 2460, -1392,
            0, 480, -1404,
            480, 780, -1404,
            8400, 8640, -1404,
            1560, 1650, -1416,
            5520, 5911.5, -1440,
            7320, 7680, -1440,
            1980, 2160, -1464,
            5460, 5520, -1464,
            5911.5, 5970, -1464,
            5370, 5460, -1526,
            5970, 6030, -1526,
            2160, 2460, -1536,
            2460, 3252, -1536,
            4050, 4260, -1536,
            4260, 4620, -1536,
            4620, 5232, -1536,
            4860, 4920, -1560,
            6030, 6060, -1560,
            780, 1152, -1620,
            1152, 1650, -1620,
            5310, 5370, -1620,
            6060, 6300, -1620,
            6300, 6480, -1620,
            7920, 8400, -1620,
            1650, 2370, -1680,
            4920, 5310, -1680,
            5310, 6120, -1680,
            0, 480, -1800,
            1260, 1650, -1800,
            2370, 3252, -1800,
            3252, 4050, -1800,
            4050, 4920, -1800,
            6480, 7680, -1800,
            7680, 8400, -1800,
            8400, 8640, -1800,
            270, 480, -1824,
            0, 1260, -1980,
            2760, 4920, -1980,
            4920, 6480, -1980,
            1260, 2760, -2040,
            0, 8640, -2160,
        ]
        let indices: [UInt8] = [
            83, 83, 83, 83, 15, 10, 15, 10, 83, 33, 15, 10, 83, 15, 10, 33,
            83, 13, 33, 33, 15, 83, 15, 33, 33, 15, 10, 33, 15, 10, 82, 33,
            15, 15, 13, 33, 13, 13, 10, 15, 10, 82, 33, 10, 15, 15, 13, 50,
            82, 33, 15, 10, 13, 33, 62, 33, 13, 62, 50, 13, 82, 13, 13, 39,
            33, 30, 62, 82, 13, 82, 50, 30, 30, 30, 82, 82, 8, 39, 50, 0,
            62, 51, 62, 30, 44, 7, 50, 0, 44, 44, 0, 62, 82, 29, 50, 48,
            0, 8, 0, 29, 0, 29, 80, 62, 7, 51, 82, 30, 7, 48, 29, 0,
            80, 7, 37, 30, 30, 80, 25, 8, 25, 51, 48, 51, 80, 66, 48, 87,
            77, 0, 73, 37, 87, 87, 0, 87, 37, 87, 87, 6, 75, 59, 37, 75,
            77, 39, 75, 77, 77, 23, 39, 23, 37, 39, 61, 77, 37, 61, 37, 39,
            31, 61, 45, 59, 37, 21, 61, 6, 31, 8, 61, 21, 45, 58, 3, 31,
            20, 73, 39, 58, 61, 66, 73, 31, 34, 61, 61, 61, 20, 77, 59, 20,
            85, 58, 16, 77, 73, 59, 59, 73, 73, 3, 66, 45, 85, 66, 66, 85,
            58, 3, 4, 58, 54, 35, 59, 41, 74, 85, 58, 3, 35, 4, 73, 72,
            41, 58, 41, 26, 71, 47, 28, 85, 41, 16, 35, 26, 28, 47, 58, 16,
            11, 4, 16, 41, 35, 46, 11, 41, 41, 47, 71, 35, 58, 76, 41, 19,
            41, 41, 36, 68, 35, 76, 65, 70, 36, 1, 70, 36, 35, 70, 14, 49,
            71, 9, 22, 67, 35, 71, 24, 76, 53, 35, 9, 49, 63, 35, 40, 9,
            38, 67, 84, 35, 40, 63, 12, 84, 40, 32, 63, 35, 64, 49, 84, 12,
            14, 49, 56, 32, 84, 14, 5, 78, 38, 40, 64, 12, 63, 35, 63, 32,
            56, 43, 64, 18, 5, 18, 5, 64, 12, 14, 27, 14, 18, 5, 40, 69,
            18, 5, 60, 81, 32, 18, 79, 81, 42, 86, 12, 55, 60, 43, 81, 81,
            42, 17, 2, 52, 57,
        ]
        let count = indices.count
        let buf = UnsafeMutablePointer<ConstelBoundary>.allocate(capacity: count)
        var i = 0
        while i < count {
            let b = i &* 3
            buf[i] = ConstelBoundary(
                raLo: coords[b],
                raHi: coords[b &+ 1],
                decLo: coords[b &+ 2],
                index: indices[i]
            )
            i &+= 1
        }
        let infoItems: [(symbol: String, name: String)] = [
            ("And", "Andromeda"),
            ("Ant", "Antila"),
            ("Aps", "Apus"),
            ("Aql", "Aquila"),
            ("Aqr", "Aquarius"),
            ("Ara", "Ara"),
            ("Ari", "Aries"),
            ("Aur", "Auriga"),
            ("Boo", "Bootes"),
            ("Cae", "Caelum"),
            ("Cam", "Camelopardis"),
            ("Cap", "Capricornus"),
            ("Car", "Carina"),
            ("Cas", "Cassiopeia"),
            ("Cen", "Centaurus"),
            ("Cep", "Cepheus"),
            ("Cet", "Cetus"),
            ("Cha", "Chamaeleon"),
            ("Cir", "Circinus"),
            ("CMa", "Canis Major"),
            ("CMi", "Canis Minor"),
            ("Cnc", "Cancer"),
            ("Col", "Columba"),
            ("Com", "Coma Berenices"),
            ("CrA", "Corona Australis"),
            ("CrB", "Corona Borealis"),
            ("Crt", "Crater"),
            ("Cru", "Crux"),
            ("Crv", "Corvus"),
            ("CVn", "Canes Venatici"),
            ("Cyg", "Cygnus"),
            ("Del", "Delphinus"),
            ("Dor", "Dorado"),
            ("Dra", "Draco"),
            ("Equ", "Equuleus"),
            ("Eri", "Eridanus"),
            ("For", "Fornax"),
            ("Gem", "Gemini"),
            ("Gru", "Grus"),
            ("Her", "Hercules"),
            ("Hor", "Horologium"),
            ("Hya", "Hydra"),
            ("Hyi", "Hydrus"),
            ("Ind", "Indus"),
            ("Lac", "Lacerta"),
            ("Leo", "Leo"),
            ("Lep", "Lepus"),
            ("Lib", "Libra"),
            ("LMi", "Leo Minor"),
            ("Lup", "Lupus"),
            ("Lyn", "Lynx"),
            ("Lyr", "Lyra"),
            ("Men", "Mensa"),
            ("Mic", "Microscopium"),
            ("Mon", "Monoceros"),
            ("Mus", "Musca"),
            ("Nor", "Norma"),
            ("Oct", "Octans"),
            ("Oph", "Ophiuchus"),
            ("Ori", "Orion"),
            ("Pav", "Pavo"),
            ("Peg", "Pegasus"),
            ("Per", "Perseus"),
            ("Phe", "Phoenix"),
            ("Pic", "Pictor"),
            ("PsA", "Pisces Austrinus"),
            ("Psc", "Pisces"),
            ("Pup", "Puppis"),
            ("Pyx", "Pyxis"),
            ("Ret", "Reticulum"),
            ("Scl", "Sculptor"),
            ("Sco", "Scorpius"),
            ("Sct", "Scutum"),
            ("Ser", "Serpens"),
            ("Sex", "Sextans"),
            ("Sge", "Sagitta"),
            ("Sgr", "Sagittarius"),
            ("Tau", "Taurus"),
            ("Tel", "Telescopium"),
            ("TrA", "Triangulum Australe"),
            ("Tri", "Triangulum"),
            ("Tuc", "Tucana"),
            ("UMa", "Ursa Major"),
            ("UMi", "Ursa Minor"),
            ("Vel", "Vela"),
            ("Vir", "Virgo"),
            ("Vol", "Volans"),
            ("Vul", "Vulpecula"),
        ]
        let infoCount = infoItems.count
        let infoBuf = UnsafeMutablePointer<(symbol: String, name: String)>.allocate(
            capacity: infoCount
        )
        var j = 0
        while j < infoCount {
            (infoBuf + j).initialize(to: infoItems[j])
            j &+= 1
        }

        // Thread-safe one-time initialization via Swift global dispatch_once (replaces C pthread_once).
        let b1875Time = AstroTime(ut: -45655.74141261017)
        let rot = EngineRotation.eqjToEqd(at: b1875Time)

        return ConstelTableStorage(
            bounds: UnsafePointer(buf),
            count: count,
            info: UnsafePointer(infoBuf),
            infoCount: infoCount,
            r00: rot.r00,
            r01: rot.r01,
            r02: rot.r02,
            r10: rot.r10,
            r11: rot.r11,
            r12: rot.r12,
            r20: rot.r20,
            r21: rot.r21,
            r22: rot.r22
        )
    }
}

enum EngineConstellation {
    static func find(rightAscension: Double, declination: Double) throws -> Constellation {
        if declination < -90.0 || declination > 90.0 {
            throw AstronomyError.invalidParameter
        }

        var ra = fmod(rightAscension, 24.0)
        if ra < 0.0 {
            ra += 24.0
        }

        let table = ConstelTableStorage.shared

        // Convert J2000 spherical (ra hours, dec deg) to unit Cartesian vector.
        let radLat = declination * EngineConstants.deg2Rad
        let radLon = (ra * 15.0) * EngineConstants.deg2Rad
        let cosLat = cos(radLat)
        let x2000 = cosLat * cos(radLon)
        let y2000 = cosLat * sin(radLon)
        let z2000 = sin(radLat)

        // Rotate J2000 to B1875 and convert back to RA/Dec.
        let x1875 = table.r00 * x2000 + table.r10 * y2000 + table.r20 * z2000
        let y1875 = table.r01 * x2000 + table.r11 * y2000 + table.r21 * z2000
        let z1875 = table.r02 * x2000 + table.r12 * y2000 + table.r22 * z2000
        let b1875 = try EngineMath.equatorFromVector(x1875, y1875, z1875)

        let xRa = (24.0 * 15.0) * b1875.ra
        let xDec = 24.0 * b1875.dec
        guard xRa.isFinite, xDec.isFinite else {
            throw AstronomyError.internalError
        }

        // ConstelBounds is ordered non-increasing by decLo, so binary-search the first
        // entry with decLo <= xDec before scanning for the first matching RA band.
        let bounds = table.bounds
        let count = table.count
        var lo = 0
        var hi = count
        while lo < hi {
            let mid = (lo &+ hi) >> 1
            if bounds[mid].decLo > xDec {
                lo = mid &+ 1
            } else {
                hi = mid
            }
        }

        var found = -1
        var i = lo
        while i < count {
            let b = bounds[i]
            if b.raHi > xRa && b.raLo <= xRa {
                found = Int(b.index)
                break
            }
            i &+= 1
        }

        guard found >= 0 && found < table.infoCount else {
            throw AstronomyError.internalError
        }

        let entry = table.info[found]
        return Constellation(
            symbol: entry.symbol,
            name: entry.name,
            rightAscension1875: b1875.ra,
            declination1875: b1875.dec
        )
    }
}

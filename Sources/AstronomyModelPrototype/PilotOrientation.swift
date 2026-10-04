// Adapted from Astronomy Engine; its MIT notice is retained in THIRD_PARTY_NOTICES.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

struct PilotMatrix {
    let xx, yx, zx, xy, yy, zy, xz, yz, zz: Double

    func apply(_ p: PilotVector, inverse: Bool = false) -> PilotVector {
        if inverse {
            return PilotVector(
                x: xx * p.x + xy * p.y + xz * p.z,
                y: yx * p.x + yy * p.y + yz * p.z,
                z: zx * p.x + zy * p.y + zz * p.z)
        }
        return PilotVector(
            x: xx * p.x + yx * p.y + zx * p.z,
            y: xy * p.x + yy * p.y + zy * p.z,
            z: xz * p.x + yz * p.y + zz * p.z)
    }
}

struct PilotOrientation {
    static let radians = Double.pi / 180.0
    static let arcsecond = 4.848136811095359935899141e-6
    struct Term: Sendable {
        let multipliers: [Double]
        let coefficients: [Double]
    }
    static let rows = (0..<PrototypeModelData.nutationRowCount).map { index in
        guard let row = PrototypeModelData.nutationRow(at: index) else {
            preconditionFailure("Generated nutation metadata exceeds its row table")
        }
        return Term(
            multipliers: row.multipliers.map(Double.init),
            coefficients: row.coefficientBits.map { Double(bitPattern: $0) })
    }
    let psi, eps, meanObliquity: Double
    let precession, nutation: PilotMatrix

    init(tt: Double) {
        let t = tt / 36525.0
        let args = [
            (485868.249036 + t * 1717915923.2178).truncatingRemainder(dividingBy: 1_296_000)
                * Self.arcsecond,
            (1287104.79305 + t * 129596581.0481).truncatingRemainder(dividingBy: 1_296_000)
                * Self.arcsecond,
            (335779.526232 + t * 1739527262.8478).truncatingRemainder(dividingBy: 1_296_000)
                * Self.arcsecond,
            (1072260.70369 + t * 1602961601.2090).truncatingRemainder(dividingBy: 1_296_000)
                * Self.arcsecond,
            (450160.398036 + t * -6962890.5431).truncatingRemainder(dividingBy: 1_296_000)
                * Self.arcsecond,
        ]
        var p = 0.0
        var e = 0.0
        for row in Self.rows.reversed() {
            var arg = 0.0
            for j in 0..<5 { arg += row.multipliers[j] * args[j] }
            let sarg = sin(arg)
            let carg = cos(arg)
            let c = row.coefficients
            p += (c[0] + c[1] * t) * sarg + c[2] * carg
            e += (c[3] + c[4] * t) * carg + c[5] * sarg
        }
        psi = -0.000135 + p * 1e-7
        eps = 0.000388 + e * 1e-7
        meanObliquity =
            (((((-0.0000000434 * t - 0.000000576) * t + 0.00200340) * t - 0.0001831) * t - 46.836769) * t
                + 84381.406) / 3600.0
        precession = Self.precession(tt: tt)
        let oblm = meanObliquity * Self.radians
        let oblt = (meanObliquity + eps / 3600.0) * Self.radians
        let angle = psi * Self.arcsecond
        let cobm = cos(oblm)
        let sobm = sin(oblm)
        let cobt = cos(oblt)
        let sobt = sin(oblt)
        let cpsi = cos(angle)
        let spsi = sin(angle)
        nutation = PilotMatrix(
            xx: cpsi, yx: -spsi * cobm, zx: -spsi * sobm,
            xy: spsi * cobt, yy: cpsi * cobm * cobt + sobm * sobt, zy: cpsi * sobm * cobt - cobm * sobt,
            xz: spsi * sobt, yz: cpsi * cobm * sobt - sobm * cobt, zz: cpsi * sobm * sobt + cobm * cobt)
    }

    func sidereal(time: PilotTime) -> Double {
        let t = time.tt / 36525.0
        let thet1 = 0.7790572732640 + 0.00273781191135448 * time.ut
        let thet3 = time.ut.truncatingRemainder(dividingBy: 1)
        var theta = 360.0 * (thet1 + thet3).truncatingRemainder(dividingBy: 1)
        if theta < 0 { theta += 360 }
        let eqeq = 15.0 * (psi * cos(meanObliquity * Self.radians) / 15.0)
        let st =
            eqeq + 0.014506
            + ((((-0.0000000368 * t - 0.000029956) * t - 0.00000044) * t + 1.3915817) * t + 4612.156534)
            * t
        var gst = (st / 3600.0 + theta).truncatingRemainder(dividingBy: 360) / 15.0
        if gst < 0 { gst += 24 }
        return gst
    }

    static func precession(tt: Double) -> PilotMatrix {
        let eps0 = 84381.406

        let t = tt / 36525

        let psia =
            (((((-0.0000000951 * t
                + 0.000132851) * t
                - 0.00114045) * t
                - 1.0790069) * t
                + 5038.481507) * t)

        let omegaa =
            (((((+0.0000003337 * t
                - 0.000000467) * t
                - 0.00772503) * t
                + 0.0512623) * t
                - 0.025754) * t + eps0)

        let chia =
            (((((-0.0000000560 * t
                + 0.000170663) * t
                - 0.00121197) * t
                - 2.3814292) * t
                + 10.556403) * t)

        let epsRadians = eps0 * Self.arcsecond

        let psiaRadians = psia * Self.arcsecond

        let omegaaRadians = omegaa * Self.arcsecond

        let chiaRadians = chia * Self.arcsecond

        let sa = sin(epsRadians)

        let ca = cos(epsRadians)

        let sb = sin(-psiaRadians)

        let cb = cos(-psiaRadians)

        let sc = sin(-omegaaRadians)

        let cc = cos(-omegaaRadians)

        let sd = sin(chiaRadians)

        let cd = cos(chiaRadians)

        let xx = cd * cb - sb * sd * cc

        let yx = cd * sb * ca + sd * cc * cb * ca - sa * sd * sc

        let zx = cd * sb * sa + sd * cc * cb * sa + ca * sd * sc

        let xy = -sd * cb - sb * cd * cc

        let yy = -sd * sb * ca + cd * cc * cb * ca - sa * cd * sc

        let zy = -sd * sb * sa + cd * cc * cb * sa + ca * cd * sc

        let xz = sb * sc

        let yz = -sc * cb * ca - sa * cc

        let zz = -sc * cb * sa + cc * ca

        return PilotMatrix(xx: xx, yx: yx, zx: zx, xy: xy, yy: yy, zy: zy, xz: xz, yz: yz, zz: zz)
    }
}

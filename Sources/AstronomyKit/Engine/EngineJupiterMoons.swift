//
//  EngineJupiterMoons.swift
//  AstronomyKit
//
//  Pure-Swift Galilean moon ephemeris (Duriez, Lainey, and Vienne L1.2).
//

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

private struct JupiterMoonTableStorage: @unchecked Sendable {
    let terms: UnsafePointer<Double>

    static let shared: JupiterMoonTableStorage = {
        let values: [Double] = [
            0.0028210960212903, 0.0000000000000000e+00, 0.0000000000000000e+00,
            -0.0001925258348666, 4.9369589722644998e+00, 1.3584836583050000e-02,
            -0.0000970803596076, 4.3188796477322002e+00, 1.3034138432430000e-02,
            -0.0000898817416500, 1.9080016428616999e+00, 3.0506486715799999e-03,
            -0.0000553101050262, 1.4936156681568999e+00, 1.2938928911549999e-02,
            0.0041510849668155, 4.0899396355450000e+00, -1.2906864146660001e-02,
            0.0006260521444113, 1.4461888986270000e+00, 3.5515522949801999e+00,
            0.0000352747346169, 2.1256287034577999e+00, 1.2727416566999999e-04,
            0.0003142172466014, 2.7964219722923001e+00, -2.3150960980000000e-03,
            0.0000904169207946, 1.0477061879627001e+00, -5.6920638196000003e-04,
            0.0044871037804314, 0.0000000000000000e+00, 0.0000000000000000e+00,
            0.0000004324367498, 1.8196456062910000e+00, 1.7822295777568000e+00,
            0.0008576433172936, 4.3188693178264002e+00, 1.3034138308049999e-02,
            0.0004549582875086, 1.4936531751079001e+00, 1.2938928819619999e-02,
            0.0003248939825174, 1.8196494533458001e+00, 1.7822295777568000e+00,
            -0.0003074250079334, 4.9377037005910998e+00, 1.3584832867240000e-02,
            0.0001982386144784, 1.9079869054759999e+00, 3.0510121286900001e-03,
            0.0001834063551804, 2.1402853388529000e+00, 1.4500978933800000e-03,
            -0.0001434383188452, 5.6222140366630002e+00, 8.9111478887838003e-01,
            -0.0000771939140944, 4.3002724372349999e+00, 2.6733443704265998e+00,
            -0.0093589104136341, 4.0899396509038999e+00, -1.2906864146660001e-02,
            0.0002988994545555, 5.9097265185595003e+00, 1.7693227079461999e+00,
            0.0002139036390350, 2.1256289300016000e+00, 1.2727418406999999e-04,
            0.0001980963564781, 2.7435168292649998e+00, 6.7797343008999997e-04,
            0.0001210388158965, 5.5839943711203004e+00, 3.2056614899999997e-05,
            0.0000837042048393, 1.6094538368039000e+00, -9.0402165808846002e-01,
            0.0000823525166369, 1.4461887708689001e+00, 3.5515522949801999e+00,
            0.0040404917832303, 1.0477063169425000e+00, -5.6920640539999997e-04,
            0.0002200421034564, 3.3368857864364001e+00, -1.2491307306999999e-04,
            0.0001662544744719, 2.4134862374710999e+00, 0.0000000000000000e+00,
            0.0000590282470983, 5.9719930968366004e+00, -3.0561602250000000e-05,
            0.0071566594572575, 0.0000000000000000e+00, 0.0000000000000000e+00,
            0.0000013930299110, 1.1586745884981000e+00, 2.6733443704265998e+00,
            0.0002310797886226, 2.1402987195941998e+00, 1.4500978438400001e-03,
            -0.0001828635964118, 4.3188672736968003e+00, 1.3034138282630000e-02,
            0.0001512378778204, 4.9373102372298003e+00, 1.3584834812520000e-02,
            -0.0001163720969778, 4.3002659861490002e+00, 2.6733443704265998e+00,
            -0.0000955478069846, 1.4936612842567001e+00, 1.2938928798570001e-02,
            0.0000815246854464, 5.6222137132535002e+00, 8.9111478887838003e-01,
            -0.0000801219679602, 1.2995922951532000e+00, 1.0034433456728999e+00,
            -0.0000607017260182, 6.4978769669238001e-01, 5.0172167043264004e-01,
            0.0014289811307319, 2.1256295942738999e+00, 1.2727413029000001e-04,
            0.0007710931226760, 5.5836330003496002e+00, 3.2064341100000001e-05,
            0.0005925911780766, 4.0899396636447998e+00, -1.2906864146660001e-02,
            0.0002045597496146, 5.2713683670371996e+00, -1.2523544076106000e-01,
            0.0001785118648258, 2.8743156721063001e-01, 8.7820792442520001e-01,
            0.0001131999784893, 1.4462127277818000e+00, 3.5515522949801999e+00,
            -0.0000658778169210, 2.2702423990985001e+00, -1.7951364394536999e+00,
            0.0000497058888328, 5.9096792204858000e+00, 1.7693227129285001e+00,
            0.0015932721570848, 3.3368862796665000e+00, -1.2491307058000000e-04,
            0.0008533093128905, 2.4133881688166001e+00, 0.0000000000000000e+00,
            0.0003513347911037, 5.9720789850126996e+00, -3.0561017709999999e-05,
            -0.0001441929255483, 1.0477061764435001e+00, -5.6920632124000004e-04,
            0.0125879701715314, 0.0000000000000000e+00, 0.0000000000000000e+00,
            0.0000035952049470, 6.4965776007116005e-01, 5.0172168165034003e-01,
            0.0000027580210652, 1.8084235781510001e+00, 3.1750660413359002e+00,
            0.0005586040123824, 2.1404207189814999e+00, 1.4500979323100001e-03,
            -0.0003805813868176, 2.7358844897852999e+00, 2.9729650620000000e-05,
            0.0002205152863262, 6.4979652596399995e-01, 5.0172167243580001e-01,
            0.0001877895151158, 1.8084787604004999e+00, 3.1750660413359002e+00,
            0.0000766916975242, 6.2720114319754998e+00, 1.3928364636651001e+00,
            0.0000747056855106, 1.2995916202344000e+00, 1.0034433456728999e+00,
            0.0073755808467977, 5.5836071576083999e+00, 3.2065099140000001e-05,
            0.0002065924169942, 5.9209831565786004e+00, 3.7648624194703001e-01,
            0.0001589869764021, 2.8744006242622999e-01, 8.7820792442520001e-01,
            -0.0001561131605348, 2.1257397865089001e+00, 1.2727441285000001e-04,
            0.0001486043380971, 1.4462134301023000e+00, 3.5515522949801999e+00,
            0.0000635073108731, 5.9096803285953996e+00, 1.7693227129285001e+00,
            0.0000599351698525, 4.1125517584797997e+00, -2.7985797954588998e+00,
            0.0000540660842731, 5.5390350845569003e+00, 2.8683408228299999e-03,
            -0.0000489596900866, 4.6218149483337996e+00, -6.2695712529518999e-01,
            0.0038422977898495, 2.4133922085556998e+00, 0.0000000000000000e+00,
            0.0022453891791894, 5.9721736773277003e+00, -3.0561255249999997e-05,
            -0.0002604479450559, 3.3368746306408998e+00, -1.2491309972000001e-04,
            0.0000332112143230, 5.5604137742336999e+00, 2.9003768850700000e-03,
        ]
        let buffer = UnsafeMutablePointer<Double>.allocate(capacity: values.count)
        for index in values.indices {
            buffer[index] = values[index]
        }
        return JupiterMoonTableStorage(terms: UnsafePointer(buffer))
    }()
}

private struct JupiterMoonSpec {
    let mu: Double
    let al0: Double
    let al1: Double
    let aStart: Int
    let aCount: Int
    let lStart: Int
    let lCount: Int
    let zStart: Int
    let zCount: Int
    let zetaStart: Int
    let zetaCount: Int
}

enum EngineJupiterMoons {
    private static let ioSpec = JupiterMoonSpec(
        mu: 2.8248942843381399e-07, al0: 1.4462132960212239e+00, al1: 3.5515522861824000e+00,
        aStart: 0, aCount: 1,
        lStart: 1, lCount: 4,
        zStart: 5, zCount: 3,
        zetaStart: 8, zetaCount: 2
    )

    private static let europaSpec = JupiterMoonSpec(
        mu: 2.8248327439289299e-07, al0: -3.7352634374713622e-01, al1: 1.7693227111234699e+00,
        aStart: 10, aCount: 2,
        lStart: 12, lCount: 8,
        zStart: 20, zCount: 7,
        zetaStart: 27, zetaCount: 4
    )

    private static let ganymedeSpec = JupiterMoonSpec(
        mu: 2.8249818418472298e-07, al0: 2.8740893911433479e-01, al1: 8.7820792358932798e-01,
        aStart: 31, aCount: 2,
        lStart: 33, lCount: 8,
        zStart: 41, zCount: 8,
        zetaStart: 49, zetaCount: 4
    )

    private static let callistoSpec = JupiterMoonSpec(
        mu: 2.8249214488990899e-07, al0: -3.6203412913757038e-01, al1: 3.7648623343382798e-01,
        aStart: 53, aCount: 3,
        lStart: 56, lCount: 6,
        zStart: 62, zCount: 9,
        zetaStart: 71, zetaCount: 4
    )

    // Rotation_JUP_EQJ (row-major transpose convention matching Astronomy_RotateState:
    // out.x = r[0][0]*x + r[1][0]*y + r[2][0]*z, etc.)
    private static let r00 = 9.99432765338654e-01
    private static let r01 = -3.36771074697641e-02
    private static let r02 = 0.00000000000000e+00
    private static let r10 = 3.03959428906285e-02
    private static let r11 = 9.02057912352809e-01
    private static let r12 = 4.30543388542295e-01
    private static let r20 = -1.44994559663353e-02
    private static let r21 = -4.30299169409101e-01
    private static let r22 = 9.02569881273754e-01

    static func moons(at time: AstroTime) throws -> JupiterMoons {
        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }
        let t = time.terrestrialTime + 18262.5
        return JupiterMoons(
            io: calcMoon(time: time, t: t, spec: ioSpec),
            europa: calcMoon(time: time, t: t, spec: europaSpec),
            ganymede: calcMoon(time: time, t: t, spec: ganymedeSpec),
            callisto: calcMoon(time: time, t: t, spec: callistoSpec)
        )
    }

    private static func calcMoon(
        time: AstroTime,
        t: Double,
        spec: JupiterMoonSpec
    ) -> StateVector {
        let terms = JupiterMoonTableStorage.shared.terms

        var a = 0.0
        var i = spec.aStart
        let aEnd = spec.aStart &+ spec.aCount
        while i < aEnd {
            let base = i &* 3
            let arg = terms[base &+ 1] + (t * terms[base &+ 2])
            a += terms[base] * cos(arg)
            i &+= 1
        }

        var al = spec.al0 + (t * spec.al1)
        i = spec.lStart
        let lEnd = spec.lStart &+ spec.lCount
        while i < lEnd {
            let base = i &* 3
            let arg = terms[base &+ 1] + (t * terms[base &+ 2])
            al += terms[base] * sin(arg)
            i &+= 1
        }
        al = fmod(al, EngineConstants.pi2)
        if al < 0.0 {
            al += EngineConstants.pi2
        }

        var k = 0.0
        var h = 0.0
        i = spec.zStart
        let zEnd = spec.zStart &+ spec.zCount
        while i < zEnd {
            let base = i &* 3
            let arg = terms[base &+ 1] + (t * terms[base &+ 2])
            let amp = terms[base]
            k += amp * cos(arg)
            h += amp * sin(arg)
            i &+= 1
        }

        var q = 0.0
        var p = 0.0
        i = spec.zetaStart
        let zetaEnd = spec.zetaStart &+ spec.zetaCount
        while i < zetaEnd {
            let base = i &* 3
            let arg = terms[base &+ 1] + (t * terms[base &+ 2])
            let amp = terms[base]
            q += amp * cos(arg)
            p += amp * sin(arg)
            i &+= 1
        }

        let an = sqrt(spec.mu / (a * a * a))

        var ee = al + k * sin(al) - h * cos(al)
        var de: Double
        repeat {
            let ce = cos(ee)
            let se = sin(ee)
            de = (al - ee + k * se - h * ce) / (1.0 - k * ce - h * se)
            ee += de
        } while abs(de) >= 1.0e-12

        let ce = cos(ee)
        let se = sin(ee)
        let dle = h * ce - k * se
        let rsam1 = -k * ce - h * se
        let asr = 1.0 / (1.0 + rsam1)
        let phi = sqrt(1.0 - k * k - h * h)
        let psi = 1.0 / (1.0 + phi)
        let x1 = a * (ce - k - psi * h * dle)
        let y1 = a * (se - h + psi * k * dle)
        let vx1 = an * asr * a * (-se - psi * h * rsam1)
        let vy1 = an * asr * a * (ce + psi * k * rsam1)
        let f2 = 2.0 * sqrt(1.0 - q * q - p * p)
        let p2 = 1.0 - 2.0 * p * p
        let q2 = 1.0 - 2.0 * q * q
        let pq = 2.0 * p * q

        let sx = x1 * p2 + y1 * pq
        let sy = x1 * pq + y1 * q2
        let sz = (q * y1 - x1 * p) * f2

        let svx = vx1 * p2 + vy1 * pq
        let svy = vx1 * pq + vy1 * q2
        let svz = (q * vy1 - vx1 * p) * f2

        // Rotate JUP -> EQJ matching Astronomy_RotateState(Rotation_JUP_EQJ, state)
        let px = r00 * sx + r10 * sy + r20 * sz
        let py = r01 * sx + r11 * sy + r21 * sz
        let pz = r02 * sx + r12 * sy + r22 * sz

        let vx = r00 * svx + r10 * svy + r20 * svz
        let vy = r01 * svx + r11 * svy + r21 * svz
        let vz = r02 * svx + r12 * svy + r22 * svz

        return StateVector(
            position: Vector3D(x: px, y: py, z: pz, time: time),
            velocity: Vector3D(x: vx, y: vy, z: vz, time: time),
            time: time
        )
    }
}

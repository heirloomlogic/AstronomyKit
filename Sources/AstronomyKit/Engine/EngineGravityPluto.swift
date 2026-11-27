//
//  EngineGravityPluto.swift
//  AstronomyKit
//
//  Pure-Swift Newtonian N-body gravity simulator, Pluto ephemeris integrator
//  with NSLock-protected segment cache, and shared 3D state helpers.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

struct EngineVec3: Sendable {
    var x: Double
    var y: Double
    var z: Double

    static let zero = EngineVec3(x: 0.0, y: 0.0, z: 0.0)
}

struct EngineBodyState: Sendable {
    var tt: Double
    var r: EngineVec3
    var v: EngineVec3

    static let zero = EngineBodyState(tt: 0.0, r: .zero, v: .zero)

    func toStateVector(at time: AstroTime) -> StateVector {
        StateVector(
            position: Vector3D(x: r.x, y: r.y, z: r.z, time: time),
            velocity: Vector3D(x: v.x, y: v.y, z: v.z, time: time),
            time: time
        )
    }
}

struct EngineGravCalc: Sendable {
    var tt: Double
    var r: EngineVec3
    var v: EngineVec3
    var a: EngineVec3

    static let zero = EngineGravCalc(tt: 0.0, r: .zero, v: .zero, a: .zero)
}

struct EngineMajorBodies: Sendable {
    var sun: EngineBodyState
    var jupiter: EngineBodyState
    var saturn: EngineBodyState
    var uranus: EngineBodyState
    var neptune: EngineBodyState
}

enum EngineGravityPluto {
    private static let plutoNumStates = 51
    private static let plutoTimeStep = 29_200.0
    private static let plutoDt = 146.0
    private static let plutoNSteps = 201
    private static let plutoMaxCrawlDays = 36_525.0

    // MARK: - Shared Physics Primitives

    @inline(__always)
    static func updatePosition(
        dt: Double,
        r: EngineVec3,
        v: EngineVec3,
        a: EngineVec3
    ) -> EngineVec3 {
        EngineVec3(
            x: r.x + (v.x + a.x * dt / 2.0) * dt,
            y: r.y + (v.y + a.y * dt / 2.0) * dt,
            z: r.z + (v.z + a.z * dt / 2.0) * dt
        )
    }

    @inline(__always)
    static func updateVelocity(dt: Double, v: EngineVec3, a: EngineVec3) -> EngineVec3 {
        EngineVec3(
            x: v.x + dt * a.x,
            y: v.y + dt * a.y,
            z: v.z + dt * a.z
        )
    }

    @inline(__always)
    private static func addPull(
        _ ax: inout Double,
        _ ay: inout Double,
        _ az: inout Double,
        sx: Double,
        sy: Double,
        sz: Double,
        gm: Double,
        major: EngineVec3
    ) {
        let dx = major.x - sx
        let dy = major.y - sy
        let dz = major.z - sz
        let r2 = dx * dx + dy * dy + dz * dz
        let pull = gm / (r2 * sqrt(r2))
        ax += dx * pull
        ay += dy * pull
        az += dz * pull
    }

    private static func smallBodyAcceleration(
        smallPos: EngineVec3,
        bary: EngineMajorBodies
    ) -> EngineVec3 {
        var ax = 0.0
        var ay = 0.0
        var az = 0.0
        let sx = smallPos.x
        let sy = smallPos.y
        let sz = smallPos.z
        addPull(&ax, &ay, &az, sx: sx, sy: sy, sz: sz, gm: EngineConstants.sunGM, major: bary.sun.r)
        addPull(&ax, &ay, &az, sx: sx, sy: sy, sz: sz, gm: EngineConstants.jupiterGM, major: bary.jupiter.r)
        addPull(&ax, &ay, &az, sx: sx, sy: sy, sz: sz, gm: EngineConstants.saturnGM, major: bary.saturn.r)
        addPull(&ax, &ay, &az, sx: sx, sy: sy, sz: sz, gm: EngineConstants.uranusGM, major: bary.uranus.r)
        addPull(&ax, &ay, &az, sx: sx, sy: sy, sz: sz, gm: EngineConstants.neptuneGM, major: bary.neptune.r)
        return EngineVec3(x: ax, y: ay, z: az)
    }

    private static func gravSimStep(
        bary2: inout EngineMajorBodies,
        tt2: Double,
        calc1: EngineGravCalc
    ) -> EngineGravCalc {
        let dt = tt2 - calc1.tt
        bary2 = EngineVsop.majorBodyBary(tt: tt2)
        let approxPos = EngineVec3(
            x: calc1.r.x + (calc1.v.x + calc1.a.x * dt / 2.0) * dt,
            y: calc1.r.y + (calc1.v.y + calc1.a.y * dt / 2.0) * dt,
            z: calc1.r.z + (calc1.v.z + calc1.a.z * dt / 2.0) * dt
        )
        let accEnd = smallBodyAcceleration(smallPos: approxPos, bary: bary2)
        let acc = EngineVec3(
            x: (accEnd.x + calc1.a.x) / 2.0,
            y: (accEnd.y + calc1.a.y) / 2.0,
            z: (accEnd.z + calc1.a.z) / 2.0
        )
        let r2 = EngineVec3(
            x: calc1.r.x + (calc1.v.x + acc.x * dt / 2.0) * dt,
            y: calc1.r.y + (calc1.v.y + acc.y * dt / 2.0) * dt,
            z: calc1.r.z + (calc1.v.z + acc.z * dt / 2.0) * dt
        )
        let v2 = EngineVec3(
            x: calc1.v.x + dt * acc.x,
            y: calc1.v.y + dt * acc.y,
            z: calc1.v.z + dt * acc.z
        )
        let a2 = smallBodyAcceleration(smallPos: r2, bary: bary2)
        return EngineGravCalc(tt: tt2, r: r2, v: v2, a: a2)
    }

    private static func gravFromState(
        bary: inout EngineMajorBodies,
        state: EngineBodyState
    ) -> EngineGravCalc {
        bary = EngineVsop.majorBodyBary(tt: state.tt)
        let r = EngineVec3(
            x: state.r.x + bary.sun.r.x,
            y: state.r.y + bary.sun.r.y,
            z: state.r.z + bary.sun.r.z
        )
        let v = EngineVec3(
            x: state.v.x + bary.sun.v.x,
            y: state.v.y + bary.sun.v.y,
            z: state.v.z + bary.sun.v.z
        )
        let a = smallBodyAcceleration(smallPos: r, bary: bary)
        return EngineGravCalc(tt: state.tt, r: r, v: v, a: a)
    }

    // MARK: - Pluto State Table & Segment Cache

    private struct PlutoTableStorage: @unchecked Sendable {
        let states: UnsafePointer<EngineBodyState>

        static let shared: PlutoTableStorage = {
            let raw: [Double] = [
                -730_000.0, -26.118207232108, -14.376168177825, 3.384402515299, 1.6339372163656e-03,
                -2.7861699588508e-03, -1.3585880229445e-03,
                -700_800.0, 41.974905202127, -0.448502952929, -12.770351505989, 7.3458569351457e-04,
                2.2785014891658e-03, 4.8619778602049e-04,
                -671_600.0, 14.706930780744, 44.269110540027, 9.353698474772, -2.1000147999800e-03, 2.2295915939915e-04,
                7.0143443551414e-04,
                -642_400.0, -29.441003929957, -6.430161530570, 6.858481011305, 8.4495803960544e-04,
                -3.0783914758711e-03, -1.2106305981192e-03,
                -613_200.0, 39.444396946234, -6.557989760571, -13.913760296463, 1.1480029005873e-03,
                2.2400006880665e-03, 3.5168075922288e-04,
                -584_000.0, 20.230380950700, 43.266966657189, 7.382966091923, -1.9754081700585e-03, 5.3457141292226e-04,
                7.5929169129793e-04,
                -554_800.0, -30.658325364620, 2.093818874552, 9.880531138071, 6.1010603013347e-05, -3.1326500935382e-03,
                -9.9346125151067e-04,
                -525_600.0, 35.737703251673, -12.587706024764, -14.677847247563, 1.5802939375649e-03,
                2.1347678412429e-03, 1.9074436384343e-04,
                -496_400.0, 25.466295188546, 41.367478338417, 5.216476873382, -1.8054401046468e-03, 8.3283083599510e-04,
                8.0260156912107e-04,
                -467_200.0, -29.847174904071, 10.636426313081, 12.297904180106, -6.3257063052907e-04,
                -2.9969577578221e-03, -7.4476074151596e-04,
                -438_000.0, 30.774692107687, -18.236637015304, -14.945535879896, 2.0113162005465e-03,
                1.9353827024189e-03, -2.0937793168297e-06,
                -408_800.0, 30.243153324028, 38.656267888503, 2.938501750218, -1.6052508674468e-03, 1.1183495337525e-03,
                8.3333973416824e-04,
                -379_600.0, -27.288984772533, 18.643162147874, 14.023633623329, -1.1856388898191e-03,
                -2.7170609282181e-03, -4.9015526126399e-04,
                -350_400.0, 24.519605196774, -23.245756064727, -14.626862367368, 2.4322321483154e-03,
                1.6062008146048e-03, -2.3369181613312e-04,
                -321_200.0, 34.505274805875, 35.125338586954, 0.557361475637, -1.3824391637782e-03, 1.3833397561817e-03,
                8.4823598806262e-04,
                -292_000.0, -23.275363915119, 25.818514298769, 15.055381588598, -1.6062295460975e-03,
                -2.3395961498533e-03, -2.4377362639479e-04,
                -262_800.0, 17.050384798092, -27.180376290126, -13.608963321694, 2.8175521080578e-03,
                1.1358749093955e-03, -4.9548725258825e-04,
                -233_600.0, 38.093671910285, 30.880588383337, -1.843688067413, -1.1317697153459e-03,
                1.6128814698472e-03, 8.4177586176055e-04,
                -204_400.0, -18.197852930878, 31.932869934309, 15.438294826279, -1.9117272501813e-03,
                -1.9146495909842e-03, -1.9657304369835e-05,
                -175_200.0, 8.528924039997, -29.618422200048, -11.805400994258, 3.1034370787005e-03,
                5.1393633292430e-04, -7.7293066202546e-04,
                -146_000.0, 40.946857258640, 25.904973592021, -4.256336240499, -8.3652705194051e-04,
                1.8129497136404e-03, 8.1564228273060e-04,
                -116_800.0, -12.326958895325, 36.881883446292, 15.217158258711, -2.1166103705038e-03,
                -1.4814420035990e-03, 1.7401209844705e-04,
                -87_600.0, -0.633258375909, -30.018759794709, -9.171932874950, 3.2016994581737e-03,
                -2.5279858672148e-04, -1.0411088271861e-03,
                -58_400.0, 42.936048423883, 20.344685584452, -6.588027007912, -5.0525450073192e-04, 1.9910074335507e-03,
                7.7440196540269e-04,
                -29_200.0, -5.975910552974, 40.611809958460, 14.470131723673, -2.2184202156107e-03,
                -1.0562361130164e-03, 3.3652250216211e-04,
                0.0, -9.875369580774, -27.978926224737, -5.753711824704, 3.0287533248818e-03, -1.1276087003636e-03,
                -1.2651326732361e-03,
                29_200.0, 43.958831986165, 14.214147973292, -8.808306227163, -1.4717608981871e-04, 2.1404187242141e-03,
                7.1486567806614e-04,
                58_400.0, 0.678136763520, 43.094461639362, 13.243238780721, -2.2358226110718e-03, -6.3233636090933e-04,
                4.7664798895648e-04,
                87_600.0, -18.282602096834, -23.305039586660, -1.766620508028, 2.5567245263557e-03,
                -1.9902940754171e-03, -1.3943491701082e-03,
                116_800.0, 43.873338744526, 7.700705617215, -10.814273666425, 2.3174803055677e-04, 2.2402163127924e-03,
                6.2988756452032e-04,
                146_000.0, 7.392949027906, 44.382678951534, 11.629500214854, -2.1932815453830e-03, -2.1751799585364e-04,
                5.9556516201114e-04,
                175_200.0, -24.981690229261, -16.204012851426, 2.466457544298, 1.8193989149580e-03,
                -2.6765419531201e-03, -1.3848283502247e-03,
                204_400.0, 42.530187039511, 0.845935508021, -12.554907527683, 6.5059779150669e-04, 2.2725657282262e-03,
                5.1133743202822e-04,
                233_600.0, 13.999526486822, 44.462363044894, 9.669418486465, -2.1079296569252e-03, 1.7533423831993e-04,
                6.9128485798076e-04,
                262_800.0, -29.184024803031, -7.371243995762, 6.493275957928, 9.3581363109681e-04, -3.0610357109184e-03,
                -1.2364201089345e-03,
                292_000.0, 39.831980671753, -6.078405766765, -13.909815358656, 1.1117769689167e-03, 2.2362097830152e-03,
                3.6230548231153e-04,
                321_200.0, 20.294955108476, 43.417190420251, 7.450091985932, -1.9742157451535e-03, 5.3102050468554e-04,
                7.5938408813008e-04,
                350_400.0, -30.669992302160, 2.318743558955, 9.973480913858, 4.5605107450676e-05, -3.1308219926928e-03,
                -9.9066533301924e-04,
                379_600.0, 35.626122155983, -12.897647509224, -14.777586508444, 1.6015684949743e-03,
                2.1171931182284e-03, 1.8002516202204e-04,
                408_800.0, 26.133186148561, 41.232139187599, 5.006401326220, -1.7857704419579e-03, 8.6046232702817e-04,
                8.0614690298954e-04,
                438_000.0, -29.576740229230, 11.863535943587, 12.631323039872, -7.2292830060955e-04,
                -2.9587820140709e-03, -7.0824296450300e-04,
                467_200.0, 29.910805787391, -19.159019294000, -15.013363865194, 2.0871080437997e-03,
                1.8848372554514e-03, -3.8528655083926e-05,
                496_400.0, 31.375957451819, 38.050372720763, 2.433138343754, -1.5546055556611e-03, 1.1699815465629e-03,
                8.3565439266001e-04,
                525_600.0, -26.360071336928, 20.662505904952, 14.414696258958, -1.3142373118349e-03,
                -2.6236647854842e-03, -4.2542017598193e-04,
                554_800.0, 22.599441488648, -24.508879898306, -14.484045731468, 2.5454108304806e-03,
                1.4917058755191e-03, -3.0243665086079e-04,
                584_000.0, 35.877864013014, 33.894226366071, -0.224524636277, -1.2941245730845e-03, 1.4560427668319e-03,
                8.4762160640137e-04,
                613_200.0, -21.538149762417, 28.204068269761, 15.321973799534, -1.7312117409010e-03,
                -2.1939631314577e-03, -1.6316913275180e-04,
                642_400.0, 13.971521374415, -28.339941764789, -13.083792871886, 2.9334630526035e-03,
                9.1860931752944e-04, -5.9939422488627e-04,
                671_600.0, 39.526942044143, 28.939897360110, -2.872799527539, -1.0068481658095e-03, 1.7021132888090e-03,
                8.3578230511981e-04,
                700_800.0, -15.576200701394, 34.399412961275, 15.466033737854, -2.0098814612884e-03,
                -1.7191109825989e-03, 7.0414782780416e-05,
                730_000.0, 4.243252837090, -30.118201690825, -10.707441231349, 3.1725847067411e-03, 1.6098461202270e-04,
                -9.0672150593868e-04,
            ]
            let buf = UnsafeMutablePointer<EngineBodyState>.allocate(capacity: plutoNumStates)
            var i = 0
            while i < plutoNumStates {
                let b = i &* 7
                buf[i] = EngineBodyState(
                    tt: raw[b],
                    r: EngineVec3(x: raw[b &+ 1], y: raw[b &+ 2], z: raw[b &+ 3]),
                    v: EngineVec3(x: raw[b &+ 4], y: raw[b &+ 5], z: raw[b &+ 6])
                )
                i &+= 1
            }
            return PlutoTableStorage(states: UnsafePointer(buf))
        }()
    }

    /// Immutable 201-step Pluto orbit segment; safely shared across threads once constructed.
    private final class PlutoSegment: @unchecked Sendable {
        let steps: UnsafeMutablePointer<EngineGravCalc>

        init(steps: UnsafeMutablePointer<EngineGravCalc>) {
            self.steps = steps
        }

        deinit {
            steps.deallocate()
        }
    }

    private final class PlutoCache: @unchecked Sendable {
        static let shared = PlutoCache()

        private let lock = NSLock()
        private var slots: [PlutoSegment?] = Array(repeating: nil, count: plutoNumStates - 1)

        func segment(at index: Int) -> PlutoSegment {
            lock.lock()
            defer { lock.unlock() }
            if let existing = slots[index] {
                return existing
            }
            let built = buildSegment(index: index)
            slots[index] = built
            return built
        }

        func reset() {
            lock.lock()
            defer { lock.unlock() }
            for i in 0..<slots.count {
                slots[i] = nil
            }
        }

        private func buildSegment(index: Int) -> PlutoSegment {
            let nsteps = plutoNSteps
            let steps = UnsafeMutablePointer<EngineGravCalc>.allocate(capacity: nsteps)
            let reverse = UnsafeMutablePointer<EngineGravCalc>.allocate(capacity: nsteps)
            defer { reverse.deallocate() }

            let table = PlutoTableStorage.shared.states
            var bary = EngineMajorBodies(
                sun: .zero,
                jupiter: .zero,
                saturn: .zero,
                uranus: .zero,
                neptune: .zero
            )
            steps[0] = gravFromState(bary: &bary, state: table[index])
            steps[nsteps - 1] = gravFromState(bary: &bary, state: table[index &+ 1])

            var stepTT = steps[0].tt
            var i = 1
            while i < nsteps &- 1 {
                stepTT += plutoDt
                steps[i] = gravSimStep(bary2: &bary, tt2: stepTT, calc1: steps[i &- 1])
                i &+= 1
            }

            stepTT = steps[nsteps &- 1].tt
            reverse[nsteps &- 1] = steps[nsteps &- 1]
            i = nsteps &- 2
            while i > 0 {
                stepTT -= plutoDt
                reverse[i] = gravSimStep(bary2: &bary, tt2: stepTT, calc1: reverse[i &+ 1])
                i &-= 1
            }

            let denom = Double(nsteps &- 1)
            i = nsteps &- 2
            while i > 0 {
                let f = Double(i) / denom
                let omf = 1.0 - f
                let fwd = steps[i]
                let rev = reverse[i]
                steps[i] = EngineGravCalc(
                    tt: fwd.tt,
                    r: EngineVec3(
                        x: omf * fwd.r.x + f * rev.r.x,
                        y: omf * fwd.r.y + f * rev.r.y,
                        z: omf * fwd.r.z + f * rev.r.z
                    ),
                    v: EngineVec3(
                        x: omf * fwd.v.x + f * rev.v.x,
                        y: omf * fwd.v.y + f * rev.v.y,
                        z: omf * fwd.v.z + f * rev.v.z
                    ),
                    a: EngineVec3(
                        x: omf * fwd.a.x + f * rev.a.x,
                        y: omf * fwd.a.y + f * rev.a.y,
                        z: omf * fwd.a.z + f * rev.a.z
                    )
                )
                i &-= 1
            }

            return PlutoSegment(steps: steps)
        }
    }

    @inline(__always)
    private static func clampIndex(_ frac: Double, count: Int) -> Int {
        let index = Int(floor(frac))
        if index < 0 {
            return 0
        }
        if index >= count {
            return count &- 1
        }
        return index
    }

    private static func calcPlutoOneWay(
        bary: inout EngineMajorBodies,
        initState: EngineBodyState,
        targetTT: Double,
        dt: Double
    ) -> EngineGravCalc {
        var calc = gravFromState(bary: &bary, state: initState)
        let n = Int(ceil((targetTT - calc.tt) / dt))
        var i = 0
        while i < n {
            let nextTT = (i &+ 1 == n) ? targetTT : (calc.tt + dt)
            calc = gravSimStep(bary2: &bary, tt2: nextTT, calc1: calc)
            i &+= 1
        }
        return calc
    }

    static func calcPluto(at time: AstroTime, heliocentric: Bool) throws -> EngineBodyState {
        let tt = time.terrestrialTime
        guard tt.isFinite else {
            throw AstronomyError.badTime
        }

        // Matches PlutoTableStorage endpoints (years 0..4000, ±730,000 TT days).
        let minTT = -730_000.0
        let maxTT = 730_000.0

        var rx: Double
        var ry: Double
        var rz: Double
        var vx: Double
        var vy: Double
        var vz: Double

        if tt < minTT || tt > maxTT {
            if tt < minTT - plutoMaxCrawlDays || tt > maxTT + plutoMaxCrawlDays {
                throw AstronomyError.badTime
            }
            let table = PlutoTableStorage.shared.states
            var bary = EngineMajorBodies(
                sun: .zero,
                jupiter: .zero,
                saturn: .zero,
                uranus: .zero,
                neptune: .zero
            )
            let calc: EngineGravCalc
            if tt < minTT {
                calc = calcPlutoOneWay(
                    bary: &bary,
                    initState: table[0],
                    targetTT: tt,
                    dt: -plutoDt
                )
            } else {
                calc = calcPlutoOneWay(
                    bary: &bary,
                    initState: table[plutoNumStates - 1],
                    targetTT: tt,
                    dt: plutoDt
                )
            }
            rx = calc.r.x
            ry = calc.r.y
            rz = calc.r.z
            vx = calc.v.x
            vy = calc.v.y
            vz = calc.v.z
            if heliocentric {
                rx -= bary.sun.r.x
                ry -= bary.sun.r.y
                rz -= bary.sun.r.z
                vx -= bary.sun.v.x
                vy -= bary.sun.v.y
                vz -= bary.sun.v.z
            }
        } else {
            let segIndex = clampIndex((tt - minTT) / plutoTimeStep, count: plutoNumStates - 1)
            let seg = PlutoCache.shared.segment(at: segIndex)
            let steps = seg.steps
            let left = clampIndex((tt - steps[0].tt) / plutoDt, count: plutoNSteps - 1)
            let s1 = steps[left]
            let s2 = steps[left &+ 1]

            let ax = (s1.a.x + s2.a.x) / 2.0
            let ay = (s1.a.y + s2.a.y) / 2.0
            let az = (s1.a.z + s2.a.z) / 2.0
            let dt1 = tt - s1.tt
            let dt2 = tt - s2.tt

            let rax = s1.r.x + (s1.v.x + ax * dt1 / 2.0) * dt1
            let ray = s1.r.y + (s1.v.y + ay * dt1 / 2.0) * dt1
            let raz = s1.r.z + (s1.v.z + az * dt1 / 2.0) * dt1
            let vax = s1.v.x + dt1 * ax
            let vay = s1.v.y + dt1 * ay
            let vaz = s1.v.z + dt1 * az

            let rbx = s2.r.x + (s2.v.x + ax * dt2 / 2.0) * dt2
            let rby = s2.r.y + (s2.v.y + ay * dt2 / 2.0) * dt2
            let rbz = s2.r.z + (s2.v.z + az * dt2 / 2.0) * dt2
            let vbx = s2.v.x + dt2 * ax
            let vby = s2.v.y + dt2 * ay
            let vbz = s2.v.z + dt2 * az

            let ramp = dt1 / plutoDt
            let omr = 1.0 - ramp
            rx = omr * rax + ramp * rbx
            ry = omr * ray + ramp * rby
            rz = omr * raz + ramp * rbz
            vx = omr * vax + ramp * vbx
            vy = omr * vay + ramp * vby
            vz = omr * vaz + ramp * vbz

            if heliocentric {
                let bary = EngineVsop.majorBodyBary(tt: tt)
                rx -= bary.sun.r.x
                ry -= bary.sun.r.y
                rz -= bary.sun.r.z
                vx -= bary.sun.v.x
                vy -= bary.sun.v.y
                vz -= bary.sun.v.z
            }
        }

        return EngineBodyState(
            tt: tt,
            r: EngineVec3(x: rx, y: ry, z: rz),
            v: EngineVec3(x: vx, y: vy, z: vz)
        )
    }

    static func resetPlutoCache() {
        PlutoCache.shared.reset()
    }
}

// MARK: - General Gravity Simulator Engine

final class EngineGravitySim: @unchecked Sendable {
    private final class Endpoint {
        var time: AstroTime
        var mercury: EngineBodyState = .zero
        var venus: EngineBodyState = .zero
        var earth: EngineBodyState = .zero
        var mars: EngineBodyState = .zero
        var jupiter: EngineBodyState = .zero
        var saturn: EngineBodyState = .zero
        var uranus: EngineBodyState = .zero
        var neptune: EngineBodyState = .zero
        var sun: EngineBodyState = .zero
        var body: EngineGravCalc = .zero

        init(time: AstroTime) {
            self.time = time
        }

        func copyFrom(_ other: Endpoint) {
            time = other.time
            mercury = other.mercury
            venus = other.venus
            earth = other.earth
            mars = other.mars
            jupiter = other.jupiter
            saturn = other.saturn
            uranus = other.uranus
            neptune = other.neptune
            sun = other.sun
            body = other.body
        }

        func calcSolarSystem() {
            let tt = time.terrestrialTime
            let sunGM = EngineConstants.sunGM
            let m0 = EngineVsop.calcVsopPosVel(bodyIndex: 0, tt: tt)
            let m1 = EngineVsop.calcVsopPosVel(bodyIndex: 1, tt: tt)
            let m2 = EngineVsop.calcVsopPosVel(bodyIndex: 2, tt: tt)
            let m3 = EngineVsop.calcVsopPosVel(bodyIndex: 3, tt: tt)
            let m4 = EngineVsop.calcVsopPosVel(bodyIndex: 4, tt: tt)
            let m5 = EngineVsop.calcVsopPosVel(bodyIndex: 5, tt: tt)
            let m6 = EngineVsop.calcVsopPosVel(bodyIndex: 6, tt: tt)
            let m7 = EngineVsop.calcVsopPosVel(bodyIndex: 7, tt: tt)

            let s0 = EngineConstants.mercuryGM / (EngineConstants.mercuryGM + sunGM)
            let s1 = EngineConstants.venusGM / (EngineConstants.venusGM + sunGM)
            let embGM = EngineConstants.earthGM + EngineConstants.moonGM
            let s2 = embGM / (embGM + sunGM)
            let s3 = EngineConstants.marsGM / (EngineConstants.marsGM + sunGM)
            let s4 = EngineConstants.jupiterGM / (EngineConstants.jupiterGM + sunGM)
            let s5 = EngineConstants.saturnGM / (EngineConstants.saturnGM + sunGM)
            let s6 = EngineConstants.uranusGM / (EngineConstants.uranusGM + sunGM)
            let s7 = EngineConstants.neptuneGM / (EngineConstants.neptuneGM + sunGM)

            var sx = s0 * m0.r.x
            var sy = s0 * m0.r.y
            var sz = s0 * m0.r.z
            var svx = s0 * m0.v.x
            var svy = s0 * m0.v.y
            var svz = s0 * m0.v.z

            sx += s1 * m1.r.x
            sy += s1 * m1.r.y
            sz += s1 * m1.r.z
            svx += s1 * m1.v.x
            svy += s1 * m1.v.y
            svz += s1 * m1.v.z

            sx += s2 * m2.r.x
            sy += s2 * m2.r.y
            sz += s2 * m2.r.z
            svx += s2 * m2.v.x
            svy += s2 * m2.v.y
            svz += s2 * m2.v.z

            sx += s3 * m3.r.x
            sy += s3 * m3.r.y
            sz += s3 * m3.r.z
            svx += s3 * m3.v.x
            svy += s3 * m3.v.y
            svz += s3 * m3.v.z

            sx += s4 * m4.r.x
            sy += s4 * m4.r.y
            sz += s4 * m4.r.z
            svx += s4 * m4.v.x
            svy += s4 * m4.v.y
            svz += s4 * m4.v.z

            sx += s5 * m5.r.x
            sy += s5 * m5.r.y
            sz += s5 * m5.r.z
            svx += s5 * m5.v.x
            svy += s5 * m5.v.y
            svz += s5 * m5.v.z

            sx += s6 * m6.r.x
            sy += s6 * m6.r.y
            sz += s6 * m6.r.z
            svx += s6 * m6.v.x
            svy += s6 * m6.v.y
            svz += s6 * m6.v.z

            sx += s7 * m7.r.x
            sy += s7 * m7.r.y
            sz += s7 * m7.r.z
            svx += s7 * m7.v.x
            svy += s7 * m7.v.y
            svz += s7 * m7.v.z

            mercury = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m0.r.x - sx, y: m0.r.y - sy, z: m0.r.z - sz),
                v: EngineVec3(x: m0.v.x - svx, y: m0.v.y - svy, z: m0.v.z - svz)
            )
            venus = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m1.r.x - sx, y: m1.r.y - sy, z: m1.r.z - sz),
                v: EngineVec3(x: m1.v.x - svx, y: m1.v.y - svy, z: m1.v.z - svz)
            )
            earth = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m2.r.x - sx, y: m2.r.y - sy, z: m2.r.z - sz),
                v: EngineVec3(x: m2.v.x - svx, y: m2.v.y - svy, z: m2.v.z - svz)
            )
            mars = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m3.r.x - sx, y: m3.r.y - sy, z: m3.r.z - sz),
                v: EngineVec3(x: m3.v.x - svx, y: m3.v.y - svy, z: m3.v.z - svz)
            )
            jupiter = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m4.r.x - sx, y: m4.r.y - sy, z: m4.r.z - sz),
                v: EngineVec3(x: m4.v.x - svx, y: m4.v.y - svy, z: m4.v.z - svz)
            )
            saturn = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m5.r.x - sx, y: m5.r.y - sy, z: m5.r.z - sz),
                v: EngineVec3(x: m5.v.x - svx, y: m5.v.y - svy, z: m5.v.z - svz)
            )
            uranus = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m6.r.x - sx, y: m6.r.y - sy, z: m6.r.z - sz),
                v: EngineVec3(x: m6.v.x - svx, y: m6.v.y - svy, z: m6.v.z - svz)
            )
            neptune = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: m7.r.x - sx, y: m7.r.y - sy, z: m7.r.z - sz),
                v: EngineVec3(x: m7.v.x - svx, y: m7.v.y - svy, z: m7.v.z - svz)
            )
            sun = EngineBodyState(
                tt: tt,
                r: EngineVec3(x: -sx, y: -sy, z: -sz),
                v: EngineVec3(x: -svx, y: -svy, z: -svz)
            )
        }

        func calcBodyAcceleration() {
            var ax = 0.0
            var ay = 0.0
            var az = 0.0
            let sx = body.r.x
            let sy = body.r.y
            let sz = body.r.z

            @inline(__always)
            func pull(_ gm: Double, _ major: EngineVec3) {
                let dx = major.x - sx
                let dy = major.y - sy
                let dz = major.z - sz
                let r2 = dx * dx + dy * dy + dz * dz
                let p = gm / (r2 * sqrt(r2))
                ax += dx * p
                ay += dy * p
                az += dz * p
            }

            pull(EngineConstants.sunGM, sun.r)
            pull(EngineConstants.mercuryGM, mercury.r)
            pull(EngineConstants.venusGM, venus.r)
            pull(EngineConstants.earthGM + EngineConstants.moonGM, earth.r)
            pull(EngineConstants.marsGM, mars.r)
            pull(EngineConstants.jupiterGM, jupiter.r)
            pull(EngineConstants.saturnGM, saturn.r)
            pull(EngineConstants.uranusGM, uranus.r)
            pull(EngineConstants.neptuneGM, neptune.r)
            body.a = EngineVec3(x: ax, y: ay, z: az)
        }

        func gravitatorState(of body: CelestialBody) -> EngineBodyState? {
            switch body {
            case .mercury: return mercury
            case .venus: return venus
            case .earth: return earth
            case .mars: return mars
            case .jupiter: return jupiter
            case .saturn: return saturn
            case .uranus: return uranus
            case .neptune: return neptune
            case .sun: return sun
            default: return nil
            }
        }

        func originState(for originBody: CelestialBody) throws -> EngineBodyState {
            if originBody == .solarSystemBarycenter {
                return EngineBodyState(tt: time.terrestrialTime, r: .zero, v: .zero)
            }
            guard let state = gravitatorState(of: originBody) else {
                throw AstronomyError.invalidBody
            }
            return state
        }
    }

    let originBody: CelestialBody
    let numBodies: Int = 1
    private var prev: Endpoint
    private var curr: Endpoint

    var currentTime: AstroTime {
        curr.time
    }

    init(origin: CelestialBody, time: AstroTime, initialState: StateVector) throws {
        guard initialState.position.x.isFinite,
            initialState.position.y.isFinite,
            initialState.position.z.isFinite,
            initialState.velocity.x.isFinite,
            initialState.velocity.y.isFinite,
            initialState.velocity.z.isFinite
        else {
            throw AstronomyError.invalidParameter
        }

        switch origin {
        case .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune, .sun,
            .solarSystemBarycenter:
            break
        default:
            throw AstronomyError.invalidBody
        }

        guard EngineMath.ephemerisTimeOk(time) else {
            throw AstronomyError.badTime
        }

        guard initialState.time.terrestrialTime == time.terrestrialTime else {
            throw AstronomyError.inconsistentTimes
        }

        self.originBody = origin
        let ep1 = Endpoint(time: time)
        ep1.body = EngineGravCalc(
            tt: initialState.time.terrestrialTime,
            r: EngineVec3(
                x: initialState.position.x,
                y: initialState.position.y,
                z: initialState.position.z
            ),
            v: EngineVec3(
                x: initialState.velocity.x,
                y: initialState.velocity.y,
                z: initialState.velocity.z
            ),
            a: .zero
        )
        ep1.calcSolarSystem()
        if origin != .solarSystemBarycenter {
            let originState = try ep1.originState(for: origin)
            ep1.body.r = EngineVec3(
                x: ep1.body.r.x + originState.r.x,
                y: ep1.body.r.y + originState.r.y,
                z: ep1.body.r.z + originState.r.z
            )
            ep1.body.v = EngineVec3(
                x: ep1.body.v.x + originState.v.x,
                y: ep1.body.v.y + originState.v.y,
                z: ep1.body.v.z + originState.v.z
            )
        }
        ep1.calcBodyAcceleration()

        let ep0 = Endpoint(time: time)
        ep0.copyFrom(ep1)
        self.prev = ep0
        self.curr = ep1
    }

    func swap() {
        let tmp = prev
        prev = curr
        curr = tmp
    }

    func update(to newTime: AstroTime) throws -> StateVector {
        guard EngineMath.ephemerisTimeOk(newTime) else {
            throw AstronomyError.badTime
        }

        let dt = newTime.terrestrialTime - curr.time.terrestrialTime

        if dt == 0.0 {
            prev.copyFrom(curr)
        } else {
            swap()
            let prevBody = prev.body
            curr.time = newTime
            curr.calcSolarSystem()
            curr.body.r = EngineGravityPluto.updatePosition(
                dt: dt,
                r: prevBody.r,
                v: prevBody.v,
                a: prevBody.a
            )
            curr.calcBodyAcceleration()
            let acc = EngineVec3(
                x: (prevBody.a.x + curr.body.a.x) / 2.0,
                y: (prevBody.a.y + curr.body.a.y) / 2.0,
                z: (prevBody.a.z + curr.body.a.z) / 2.0
            )
            curr.body.tt = newTime.terrestrialTime
            curr.body.r = EngineGravityPluto.updatePosition(
                dt: dt,
                r: prevBody.r,
                v: prevBody.v,
                a: acc
            )
            curr.body.v = EngineGravityPluto.updateVelocity(dt: dt, v: prevBody.v, a: acc)
            curr.calcBodyAcceleration()

            let br = curr.body.r
            let bv = curr.body.v
            let ba = curr.body.a
            guard br.x.isFinite, br.y.isFinite, br.z.isFinite,
                bv.x.isFinite, bv.y.isFinite, bv.z.isFinite,
                ba.x.isFinite, ba.y.isFinite, ba.z.isFinite
            else {
                swap()
                throw AstronomyError.badVector
            }
        }

        var rx = curr.body.r.x
        var ry = curr.body.r.y
        var rz = curr.body.r.z
        var vx = curr.body.v.x
        var vy = curr.body.v.y
        var vz = curr.body.v.z
        if originBody != .solarSystemBarycenter {
            let originState = try curr.originState(for: originBody)
            rx -= originState.r.x
            ry -= originState.r.y
            rz -= originState.r.z
            vx -= originState.v.x
            vy -= originState.v.y
            vz -= originState.v.z
        }
        return StateVector(
            position: Vector3D(x: rx, y: ry, z: rz, time: newTime),
            velocity: Vector3D(x: vx, y: vy, z: vz, time: newTime),
            time: newTime
        )
    }

    func bodyState(of body: CelestialBody) throws -> StateVector {
        guard let bstate = curr.gravitatorState(of: body) else {
            throw AstronomyError.invalidBody
        }
        let originState = try curr.originState(for: originBody)
        return StateVector(
            position: Vector3D(
                x: bstate.r.x - originState.r.x,
                y: bstate.r.y - originState.r.y,
                z: bstate.r.z - originState.r.z,
                time: curr.time
            ),
            velocity: Vector3D(
                x: bstate.v.x - originState.v.x,
                y: bstate.v.y - originState.v.y,
                z: bstate.v.z - originState.v.z,
                time: curr.time
            ),
            time: curr.time
        )
    }
}

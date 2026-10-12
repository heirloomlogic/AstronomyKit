import Foundation
import Testing

@testable import AstronomyKit

@Suite("Public apparent-place integration")
struct EngineApparentIntegrationTests {
    @Test("The public Moon applies light time and distinguishes astrometric and apparent place")
    func lunarCorrections() throws {
        let time = AstroTime(tt: 100, deltaTModel: .jplHorizons)
        let geometric = try Moon.geocentricPosition(at: time)
        let natural = try CelestialBody.moon.geocentricPosition(at: time, aberration: .none)
        let apparent = try CelestialBody.moon.geocentricPosition(at: time, aberration: .corrected)
        let g = SIMD3(geometric.x, geometric.y, geometric.z)
        let n = SIMD3(natural.x, natural.y, natural.z)
        let a = SIMD3(apparent.x, apparent.y, apparent.z)
        #expect(Engine.ApparentPlace.norm(n - g) > 1e-8)
        #expect(Engine.ApparentPlace.norm(a - g) > 1e-10)
        #expect(Engine.ApparentPlace.norm(a - n) > 1e-8)
    }

    @Test("The dedicated Sun and general apparent state share the observation-date solution")
    func solarRoutes() throws {
        for tt in [-Engine.acceptedTTDays, 0, 100, Engine.acceptedTTDays] {
            let time = AstroTime(tt: tt, deltaTModel: .jplHorizons)
            let expected = try CelestialBody.sun.geocentricPosition(at: time).toEcliptic()
            let actual = try Sun.position(at: time)
            #expect(actual.longitude == expected.longitude)
            #expect(actual.latitude == expected.latitude)
            let state = try Sun.eclipticState(at: time)
            #expect(state.longitude == expected.longitude)
            #expect(state.latitude == expected.latitude)
        }
    }
    @Test("Analytic observer velocity and acceleration differentiate the selected site trajectory")
    func observerDerivatives() throws {
        let observers = [
            Observer(latitude: 0, longitude: 0, height: 0),
            Observer(latitude: 67.3, longitude: -123.7, height: 4321),
        ]
        for tt in [-1_400_000.25, -1234.5, 0.125, 8765.4321, 1_400_000.25] {
            let h = 0.0001
            for observer in observers {
                func sample(_ offset: Double) throws -> Engine.ApparentPlace.Kinematics {
                    try Engine.ApparentPlace.siteKinematics(
                        observer, at: Engine.Time(ut: tt - 0.001 + offset, tt: tt + offset, deltaTModel: .jplHorizons))
                }
                let mid = try sample(0)
                let before = try sample(-h)
                let after = try sample(h)
                let dt = (tt + h) - (tt - h)
                let velocity = (after.motion.value - before.motion.value) / dt
                let acceleration = (after.motion.rate - before.motion.rate) / dt
                #expect(Engine.ApparentPlace.norm(velocity - mid.motion.rate) < 3e-10)
                #expect(Engine.ApparentPlace.norm(acceleration - mid.acceleration) < 2e-9)
            }
        }
    }

    @Test("Every apparent body retains position/state identity and analytic rates")
    func bodyRates() throws {
        let bodies: [CelestialBody] = [
            .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
        ]
        for tt in [-1_000_000.25, -1234.1234, 1234.1234, 1_000_000.25] {
            let h = 0.001
            for body in bodies {
                for mode: Aberration in [.none, .corrected] {
                    func sample(_ offset: Double) throws -> Engine.State<Engine.EQJ> {
                        try Engine.Positions.geocentricState(
                            of: body, at: Engine.Time(ut: tt + offset, tt: tt + offset, deltaTModel: .jplHorizons),
                            aberration: mode)
                    }
                    let mid = try sample(0)
                    let position = try Engine.Positions.geocentricPosition(of: body, at: mid.time, aberration: mode)
                    #expect(SIMD3(position.x, position.y, position.z) == mid.positionVector)
                    let first = try sample(-h)
                    let last = try sample(h)
                    let difference = (last.positionVector - first.positionVector) / ((tt + h) - (tt - h))
                    #expect(Engine.ApparentPlace.norm(difference - mid.velocityVector) < 2e-8)
                }
            }
        }
    }

    @Test(
        "Diagnostic lunar obscuration decomposition",
        .enabled(if: ProcessInfo.processInfo.environment["APPARENT_DIAGNOSTIC"] == "1"))
    func diagnoseLunarObscuration() throws {
        let source = IndependentReferenceArchive.shared.lunarEclipseObscurations[1]
        let seed = IndependentReferenceDate.engine(source.universalTimeSearchSeed)
        let eclipse = try Engine.Events.searchLunarEclipse(after: seed.adding(days: -10))
        let time = eclipse.peak
        let moon = try Engine.Positions.geocentricPosition(of: .moon, at: time, aberration: .corrected)
        let geometric = try Engine.Moon.geocentricPosition(at: time)
        let sun = try Engine.Positions.geocentricPosition(of: .sun, at: time, aberration: .corrected)
        let oldSun = try Engine.LightTravel.correct(at: time) { backdated in
            let earth = try Engine.Planet.earth.heliocentricPosition(at: backdated)
            return Engine.Vector<Engine.EQJ>(x: -earth.x, y: -earth.y, z: -earth.z, time: backdated)
        }
        func separation(_ t: Engine.Time) throws -> Double {
            let s = try Engine.Positions.geocentricPosition(of: .sun, at: t, aberration: .corrected)
            let m = try Engine.Positions.geocentricPosition(of: .moon, at: t, aberration: .corrected)
            return EnginePlutoConsumerQualificationTests.angle(SIMD3(-s.x, -s.y, -s.z), SIMD3(m.x, m.y, m.z))
        }
        let angularPeak = try #require(
            Engine.Search.ascendingRoot(
                from: time.adding(days: -0.01), to: time.adding(days: 0.01), toleranceSeconds: 0.001
            ) { t in
                try separation(t.adding(days: 1e-5)) - separation(t.adding(days: -1e-5))
            })
        print(
            "LUNAR_PEAK_OBJECTIVE", "axisTT", time.tt, "angularTT", angularPeak.tt, "differenceSeconds",
            (angularPeak.tt - time.tt) * Engine.secondsPerDay)
        let am = try Engine.Positions.geocentricPosition(of: .moon, at: angularPeak, aberration: .corrected)
        let ass = try Engine.Positions.geocentricPosition(of: .sun, at: angularPeak, aberration: .corrected)
        let ash = try Engine.Shadows.lunarEarthShadow(
            target: am, direction: Engine.Vector<Engine.EQJ>(x: -ass.x, y: -ass.y, z: -ass.z, time: angularPeak))
        let ar = try Engine.Shadows.projectedDiscRadius(
            physicalRadiusKilometers: Engine.Shadows.moonMeanRadiusKilometers,
            distanceKilometers: am.length * Engine.kilometersPerAU)
        print(
            "LUNAR_ANGULAR_PEAK_OBSCURATION",
            Engine.Shadows.obscuration(
                firstRadius: ar, secondRadius: ash.umbraRadiusKilometers, separation: ash.axisDistanceKilometers))
        for (sn, sv) in [("newSun", sun), ("oldSun", oldSun)] {
            for (mn, mv) in [("apparentMoon", moon), ("geometricMoon", geometric)] {
                let direction = Engine.Vector<Engine.EQJ>(x: -sv.x, y: -sv.y, z: -sv.z, time: time)
                let shadow = try Engine.Shadows.lunarEarthShadow(target: mv, direction: direction)
                let radius = try Engine.Shadows.projectedDiscRadius(
                    physicalRadiusKilometers: Engine.Shadows.moonMeanRadiusKilometers,
                    distanceKilometers: shadow.target.length * Engine.kilometersPerAU)
                let obscuration = Engine.Shadows.obscuration(
                    firstRadius: radius,
                    secondRadius: shadow.umbraRadiusKilometers, separation: shadow.axisDistanceKilometers)
                print(
                    "LUNAR_DIAGNOSTIC", sn, mn, "TT", time.tt, "obscuration", obscuration,
                    "distanceKm", mv.length * Engine.kilometersPerAU, "axisKm", shadow.axisDistanceKilometers)
            }
        }
    }

    struct HorizonsFixture: Decodable {
        struct Row: Decodable {
            let body: String
            let tt: Double
            let observer: [Double]?
            let apparentICRFDeg: [Double]
            let astrometricICRFDeg: [Double]
            let distanceAU: Double
            let tdbMinusUTSeconds: Double
            let angularToleranceArcseconds: Double
            let correctionToleranceArcseconds: Double
            let rangeToleranceKm: Double
        }
        let rows: [Row]
    }

    @Test("Sixty independent Horizons directions and angular corrections retain measured gates")
    func horizonsApparent() throws {
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            HorizonsFixture.self,
            from: Data(
                contentsOf:
                    root.appendingPathComponent("Scripts/apparent-place-data/horizons-fixtures.json")))
        let bodies: [String: CelestialBody] = [
            "sun": .sun, "moon": .moon, "mercury": .mercury, "venus": .venus,
            "mars": .mars, "jupiter": .jupiter, "saturn": .saturn, "uranus": .uranus, "neptune": .neptune,
            "pluto": .pluto,
        ]
        #expect(fixture.rows.count == 60)
        var residuals: [[String: Any]] = []
        for row in fixture.rows {
            let body = try #require(bodies[row.body])
            let ut = row.tt + (Engine.TDB.offsetSeconds(tt: row.tt) - row.tdbMinusUTSeconds) / Engine.secondsPerDay
            let time = Engine.Time(ut: ut, tt: row.tt, deltaTModel: .jplHorizons)
            let native: SIMD3<Double>
            let nativeDistance: Double
            if let site = row.observer {
                let observer = Observer(latitude: site[1], longitude: site[0], height: site[2] * 1000)
                let eq = try body.equatorial(at: AstroTime(time), from: observer, equatorDate: .j2000)
                let ra = eq.rightAscension * .pi / 12
                let dec = eq.declination * .pi / 180
                native = SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
                nativeDistance = eq.distance
            } else {
                let v = try body.geocentricPosition(at: AstroTime(time))
                native = SIMD3(v.x, v.y, v.z)
                nativeDistance = v.magnitude
            }
            let ra = row.apparentICRFDeg[0] * .pi / 180
            let dec = row.apparentICRFDeg[1] * .pi / 180
            let reference = Engine.FrameBias.icrsToEqj.apply(
                to: SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec)))
            let residual = EnginePlutoConsumerQualificationTests.angle(native, reference) * 60
            let astrometric: SIMD3<Double>
            if let site = row.observer {
                let eq = try body.equatorial(
                    at: AstroTime(time), from: Observer(latitude: site[1], longitude: site[0], height: site[2] * 1000),
                    equatorDate: .j2000, aberration: .none)
                let a = eq.rightAscension * .pi / 12
                let d = eq.declination * .pi / 180
                astrometric = SIMD3(cos(d) * cos(a), cos(d) * sin(a), sin(d))
            } else {
                let v = try body.geocentricPosition(at: AstroTime(time), aberration: .none)
                astrometric = SIMD3(v.x, v.y, v.z)
            }
            let aa = row.astrometricICRFDeg[0] * .pi / 180
            let dd = row.astrometricICRFDeg[1] * .pi / 180
            let ar = Engine.FrameBias.icrsToEqj.apply(to: SIMD3(cos(dd) * cos(aa), cos(dd) * sin(aa), sin(dd)))
            let astrometricResidual = EnginePlutoConsumerQualificationTests.angle(astrometric, ar) * 60
            let unit = native / sqrt((native * native).sum())
            let astrometricUnit = astrometric / sqrt((astrometric * astrometric).sum())
            let correctionDifference: SIMD3<Double> = unit - astrometricUnit - (reference - ar)
            let correctionNorm: Double = sqrt((correctionDifference * correctionDifference).sum())
            let correctionResidual: Double = correctionNorm * 180 / .pi * 3600
            #expect(
                residual < row.angularToleranceArcseconds,
                "\(row.body) TT \(row.tt) topocentric \(row.observer != nil): \(residual) arcsec")
            #expect(
                correctionResidual < row.correctionToleranceArcseconds,
                "\(row.body): angular correction residual \(correctionResidual) arcsec")
            let rangeError = abs(nativeDistance - row.distanceAU) * Engine.kilometersPerAU
            #expect(rangeError <= row.rangeToleranceKm, "\(row.body): range residual \(rangeError) km")
            residuals.append([
                "body": row.body, "tt": row.tt, "topocentric": row.observer != nil, "residualArcseconds": residual,
                "astrometricResidualArcseconds": astrometricResidual,
                "correctionResidualArcseconds": correctionResidual, "nativeVector": [native.x, native.y, native.z],
                "referenceVector": [reference.x, reference.y, reference.z], "referenceDistanceAU": row.distanceAU,
                "nativeDistanceAU": nativeDistance, "rangeErrorKm": rangeError,
            ])
        }
        if let path = ProcessInfo.processInfo.environment["APPARENT_HORIZONS_CAPTURE"] {
            try JSONSerialization.data(withJSONObject: residuals, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path))
        }
    }

    struct IntegrationReference: Decodable {
        struct Site: Decodable {
            let tt: Double
            let ut: Double
            let observer: [Double]
            let position: [String]
            let velocity: [String]
            let acceleration: [String]
        }
        struct Overlap: Decodable {
            struct Source: Decodable {
                let jdTT: String
                let raDegrees: String
                let declinationDegrees: String
                let distanceAU: String
            }
            struct Expected: Decodable {
                let obscuration: String
                let axisDistanceKilometers: String
                let umbraRadiusKilometers: String
                let moonRadiusKilometers: String
            }
            let sun: Source
            let moon: Source
            let expected: Expected
            let arithmeticToleranceFraction: Double
        }
        struct Altitude: Decodable {
            let ut: Double
            let tt: Double
            let altitude: String
        }
        let siteCases: [Site]
        let lunarOverlap: Overlap
        let altitudeSample: Altitude
        static func load() throws -> Self {
            let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
            return try JSONDecoder().decode(
                Self.self,
                from: Data(
                    contentsOf: root.appendingPathComponent("Scripts/apparent-place-data/integration-reference.json")))
        }
    }

    @Test("Observer motion matches independently differentiated 80-digit trajectories")
    func independentSiteMotion() throws {
        let cases = try IntegrationReference.load().siteCases
        #expect(cases.count == 4)
        for row in cases {
            let time = Engine.Time(ut: row.ut, tt: row.tt, deltaTModel: .espenakMeeus)
            let observer = Observer(latitude: row.observer[0], longitude: row.observer[1], height: row.observer[2])
            let actual = try Engine.ApparentPlace.siteKinematics(observer, at: time)
            for (values, expected, tolerance) in [
                (actual.motion.value, row.position, 5e-16), (actual.motion.rate, row.velocity, 2e-15),
                (actual.acceleration, row.acceleration, 2e-14),
            ] {
                for i in 0..<3 {
                    #expect(
                        abs(values[i] - (try #require(Double(expected[i])))) < tolerance, "TT \(row.tt) component \(i)")
                }
            }
        }
    }

    @Test("Archived Horizons vectors reproduce independent lunar-overlap arithmetic")
    func independentLunarOverlap() throws {
        let row = try IntegrationReference.load().lunarOverlap
        let tt = try #require(Double(row.sun.jdTT)) - 2_451_545
        let time = Engine.Time(tt: tt, deltaTModel: .jplHorizons)
        func vector(_ source: IntegrationReference.Overlap.Source, sign: Double) throws -> Engine.Vector<Engine.EQJ> {
            let a = try #require(Double(source.raDegrees)) * .pi / 180
            let d = try #require(Double(source.declinationDegrees)) * .pi / 180
            let r = try #require(Double(source.distanceAU)) * sign
            let icrs = SIMD3(r * cos(d) * cos(a), r * cos(d) * sin(a), r * sin(d))
            let eqj = Engine.FrameBias.icrsToEqj.apply(to: icrs)
            return Engine.Vector(x: eqj.x, y: eqj.y, z: eqj.z, time: time)
        }
        let moon = try vector(row.moon, sign: 1)
        let shadow = try Engine.Shadows.lunarEarthShadow(target: moon, direction: vector(row.sun, sign: -1))
        let radius = try Engine.Shadows.projectedDiscRadius(
            physicalRadiusKilometers: Engine.Shadows.moonMeanRadiusKilometers,
            distanceKilometers: moon.length * Engine.kilometersPerAU)
        let actual = Engine.Shadows.obscuration(
            firstRadius: radius, secondRadius: shadow.umbraRadiusKilometers, separation: shadow.axisDistanceKilometers)
        #expect(abs(actual - (try #require(Double(row.expected.obscuration)))) < row.arithmeticToleranceFraction)
        #expect(abs(shadow.axisDistanceKilometers - (try #require(Double(row.expected.axisDistanceKilometers)))) < 1e-7)
        #expect(abs(shadow.umbraRadiusKilometers - (try #require(Double(row.expected.umbraRadiusKilometers)))) < 1e-7)
        #expect(abs(radius - (try #require(Double(row.expected.moonRadiusKilometers)))) < 1e-7)
    }

    @Test("Lunar apparent light time resolves an adjacent-emission lattice cycle")
    func lunarEmissionLattice() throws {
        let center = 6.536749192681518
        let originalObserver = try Engine.ApparentPlace.earthBarycentricKinematics(tt: center)
        var originalDelay = 0.0
        var emissions: [Double] = []
        var oldWouldStop = false
        for _ in 0..<20 {
            let emission = center - originalDelay
            emissions.append(emission)
            let source = try Engine.ApparentPlace.bodyMotion(.moon, tt: emission)
            let range = Engine.ApparentPlace.norm(source.value - originalObserver.motion.value)
            let next =
                range / Engine.speedOfLightAUPerDay
                - (Engine.TDB.offsetSeconds(tt: center) - Engine.TDB.offsetSeconds(tt: emission)) / Engine.secondsPerDay
            oldWouldStop = oldWouldStop || abs(next - originalDelay) <= 4 * next.ulp || center - next == emission
            originalDelay = next
        }
        #expect(!oldWouldStop)
        #expect(emissions[18] == emissions[16] && emissions[19] == emissions[17])
        #expect(abs(emissions[18] - emissions[19]) == center.ulp)
        for tt in [center.nextDown, center, center.nextUp] {
            let time = Engine.Time(tt: tt, deltaTModel: .espenakMeeus)
            let observer = try Engine.ApparentPlace.earthBarycentricKinematics(tt: tt)
            let result = try Engine.ApparentPlace.retardedState(atTT: tt, observer: observer.motion) {
                try Engine.ApparentPlace.bodyMotion(.moon, tt: $0)
            }
            let elapsed =
                tt - result.emissionTT
                + (Engine.TDB.offsetSeconds(tt: tt) - Engine.TDB.offsetSeconds(tt: result.emissionTT))
                / Engine.secondsPerDay
            #expect(abs(elapsed - result.lightTimeDays) <= 2 * result.emissionTT.ulp)
            #expect(result.iterations <= 20)
            _ = try CelestialBody.moon.geocentricPosition(at: AstroTime(time))
        }
    }

    @Test("Public endpoint routes retain strict reception guards and covered emissions")
    func publicEndpointsAndErrors() throws {
        let bodies: [CelestialBody] = [
            .sun, .moon, .mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
        ]
        let site = Observer(latitude: 35.6, longitude: -82.55, height: 420)
        for tt in [-Engine.acceptedTTDays, Engine.acceptedTTDays] {
            let time = AstroTime(tt: tt, deltaTModel: .espenakMeeus)
            for body in bodies {
                for mode in [Aberration.none, .corrected] {
                    _ = try body.geocentricPosition(at: time, aberration: mode)
                    _ = try body.equatorial(at: time, from: site, equatorDate: .ofDate, aberration: mode)
                }
                if body != .sun {
                    _ = try body.angleFromSun(at: time)
                    _ = try body.elongation(at: time)
                }
            }
            let moon = Engine.Ecliptic(
                try Engine.Positions.geocentricPosition(of: .moon, at: time.engine, aberration: .corrected))
            let sun = try Engine.Positions.sunPosition(at: time.engine)
            #expect(
                try Engine.Events.moonPhaseAngle(at: time.engine)
                    == Engine.normalizedLongitude(moon.longitude - sun.longitude))
        }
        for tt in [-Engine.acceptedTTDays.nextUp, Engine.acceptedTTDays.nextUp, .nan, .infinity, -.infinity] {
            let time = AstroTime(tt: tt, deltaTModel: .espenakMeeus)
            for mode in [Aberration.none, .corrected] {
                #expect(throws: AstronomyError.badTime) {
                    try CelestialBody.moon.geocentricPosition(at: time, aberration: mode)
                }
                #expect(throws: AstronomyError.badTime) {
                    try CelestialBody.sun.equatorial(at: time, from: site, equatorDate: .j2000, aberration: mode)
                }
            }
        }
        let now = AstroTime(tt: 100, deltaTModel: .espenakMeeus)
        _ = try CelestialBody.venus.backdatedPosition(at: now, seenFrom: .sun, aberration: .none)
        #expect(throws: AstronomyError.badVector) { try CelestialBody.venus.backdatedPosition(at: now, seenFrom: .sun) }
        #expect(try CelestialBody.sun.backdatedPosition(at: now, seenFrom: .sun).magnitude == 0)
    }

    @Test("Angular integration distinguishes omitted deflection and site aberration")
    func omittedEffects() throws {
        let time = Engine.Time(tt: 0.125, deltaTModel: .espenakMeeus)
        let earth = try Engine.ApparentPlace.earthBarycentricKinematics(tt: time.tt)
        let sun = try Engine.ApparentPlace.sunBarycentricKinematics(tt: time.tt)
        let retarded = try Engine.ApparentPlace.retardedState(atTT: time.tt, observer: earth.motion) {
            try Engine.ApparentPlace.bodyMotion(.mars, tt: $0)
        }
        let beta = try Engine.ApparentPlace.observerBeta(earth, atTT: time.tt)
        let noDeflection = try Engine.ApparentPlace.aberration(
            direction: retarded.displacement.normalized(), beta: beta,
            sunDistance: Engine.ApparentPlace.length(earth.motion - sun.motion)
        ).value
        let full = try Engine.ApparentPlace.geocentricMotion(body: .mars, at: time, aberration: .corrected).value
        #expect(EnginePlutoConsumerQualificationTests.angle(noDeflection, full) * 60 > 0.0002)
        let site = try Engine.ApparentPlace.siteKinematics(Observer(latitude: 35.6, longitude: -82.55), at: time)
        let observer = Engine.ApparentPlace.Kinematics(
            motion: earth.motion + site.motion, acceleration: earth.acceleration + site.acceleration)
        let topocentric = try Engine.ApparentPlace.retardedState(atTT: time.tt, observer: observer.motion) {
            try Engine.ApparentPlace.bodyMotion(.sun, tt: $0)
        }
        let noDiurnal = try Engine.ApparentPlace.correctedMotion(
            topocentric.displacement, sunToObserver: observer.motion - sun.motion, beta: beta, solarSource: true
        ).value
        let complete = try Engine.ApparentPlace.solution(
            body: .sun, at: time, observer: observer, aberration: .corrected
        ).motion.value
        #expect(EnginePlutoConsumerQualificationTests.angle(noDiurnal, complete) * 60 > 0.05)
    }
}

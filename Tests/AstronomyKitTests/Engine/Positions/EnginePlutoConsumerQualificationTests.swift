import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native Pluto geocentric consumer qualification")
struct EnginePlutoConsumerQualificationTests {
    struct Row: Decodable {
        let tt: Double
        let target: Int
        let astrometricICRFDeg: [Double]
        let apparentICRFDeg: [Double]
        let apparentEQDDeg: [Double]
        let lightTimeMinutes: Double
    }
    struct Fixture: Decodable { let rows: [Row] }

    static func vector<F>(_ v: Engine.Vector<F>) -> SIMD3<Double> { SIMD3(v.x, v.y, v.z) }
    static func direction(_ degrees: [Double]) -> SIMD3<Double> {
        let ra = degrees[0] * .pi / 180
        let dec = degrees[1] * .pi / 180
        return SIMD3(cos(dec) * cos(ra), cos(dec) * sin(ra), sin(dec))
    }
    static func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        let c = SIMD3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
        return atan2((c * c).sum().squareRoot(), (a * b).sum()) * 180 / .pi * 60
    }
    static func write(_ value: Any, key: String) throws {
        if let path = ProcessInfo.processInfo.environment[key] {
            try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: path))
        }
    }

    @Test("Frozen independent observer directions retain the owner’s one-arcminute target")
    func observerDirections() throws {
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        let fixture = try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/pluto-data/observer-fixtures.json")))
        #expect(fixture.rows.count == 20)
        var measurements: [[String: Any]] = []
        var omittedEarthFailures = 0
        var omittedFrameFailures = 0
        for row in fixture.rows {
            let time = Engine.Time(tt: row.tt, deltaTModel: .jplHorizons)
            let astrometric = try Engine.Positions.geocentricPosition(of: .pluto, at: time, aberration: .none)
            let apparent = try Engine.Positions.geocentricPosition(of: .pluto, at: time, aberration: .corrected)
            let eqd = Engine.FrameRotation.eqjToEqd(time).apply(to: apparent)
            let expectedAstrometric = Engine.FrameBias.icrsToEqj.apply(to: Self.direction(row.astrometricICRFDeg))
            let expectedApparent = Engine.FrameBias.icrsToEqj.apply(to: Self.direction(row.apparentICRFDeg))
            let expectedEQD = Self.direction(row.apparentEQDDeg)
            let errors = [
                Self.angle(Self.vector(astrometric), expectedAstrometric),
                Self.angle(Self.vector(apparent), expectedApparent), Self.angle(Self.vector(eqd), expectedEQD),
            ]
            for error in errors { #expect(error <= 1, "TT \(row.tt), target \(row.target): \(errors) arcmin") }
            #expect(astrometric.time.tt == row.tt && apparent.time.tt == row.tt)
            let emission = try Engine.Positions.backdatedPosition(
                of: .pluto, seenFrom: .earth, at: time, aberration: .none)
            #expect(emission.time.tt < time.tt && emission.time.tt >= -766_525)
            // This checks the existing numerical stopping rule, not a new physical light-time accuracy limit.
            let next = time.adding(days: -emission.length / Engine.speedOfLightAUPerDay)
            #expect(abs(next.tt - emission.time.tt) < 1e-9)
            let heliocentric = try Engine.Positions.heliocentricPosition(of: .pluto, at: time)
            let omittedEarth = Self.angle(Self.vector(heliocentric), expectedAstrometric)
            let omittedFrame = Self.angle(Self.vector(apparent), expectedEQD)
            if omittedEarth > 1 { omittedEarthFailures += 1 }
            if omittedFrame > 1 { omittedFrameFailures += 1 }
            measurements.append([
                "tt": row.tt, "target": row.target, "astrometricArcminutes": errors[0],
                "apparentICRFArcminutes": errors[1], "apparentEQDArcminutes": errors[2],
                "emissionTT": emission.time.tt, "nativeLightTimeMinutes": (time.tt - emission.time.tt) * 1440,
                "horizonsLightTimeMinutes": row.lightTimeMinutes,
                "omittedEarthArcminutes": omittedEarth, "omittedFrameArcminutes": omittedFrame,
                "aberrationDisplacementArcminutes": Self.angle(Self.vector(astrometric), Self.vector(apparent)),
            ])
        }
        #expect(omittedEarthFailures >= 15 && omittedFrameFailures >= 15)
        try Self.write(
            [
                "rows": measurements, "omittedEarthFailures": omittedEarthFailures,
                "omittedFrameFailures": omittedFrameFailures,
            ], key: "PLUTO_OBSERVER_OUTPUT")
    }

    @Test("Observation endpoints accept retarded emission without changing the direct state range")
    func retardedDomain() throws {
        for tt in [-766_525.0, 766_525.0] {
            _ = try Engine.Positions.heliocentricPosition(
                of: .pluto, at: Engine.Time(tt: tt, deltaTModel: .jplHorizons))
        }
        for tt in [(-766_525.0).nextDown, 766_525.0.nextUp, .nan, .infinity, -.infinity] {
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Positions.heliocentricPosition(
                    of: .pluto, at: Engine.Time(tt: tt, deltaTModel: .jplHorizons))
            }
        }
        for aberration in [Aberration.none, .corrected] {
            for tt in [(-766_525.0).nextDown, 766_525.0.nextUp, .nan, .infinity, -.infinity] {
                #expect(throws: AstronomyError.badTime) {
                    _ = try Engine.Positions.geocentricPosition(
                        of: .pluto, at: Engine.Time(tt: tt, deltaTModel: .jplHorizons), aberration: aberration)
                }
            }
            let initialInterval = (0...12).map { -766_525.0 + Double($0) / 40 }
            for tt in initialInterval + [-766_524.0, 766_524.0, 766_525.0] {
                let time = Engine.Time(tt: tt, deltaTModel: .jplHorizons)
                let result = try Engine.Positions.geocentricPosition(of: .pluto, at: time, aberration: aberration)
                #expect(result.time.tt == tt && result.length.isFinite)
            }
        }
    }

    @Test("Every native retarded Pluto consumer accepts the lower observation endpoint")
    func lowerEndpointConsumers() throws {
        let time = Engine.Time(tt: -766_525, deltaTModel: .jplHorizons)
        for aberration in [Aberration.none, .corrected] {
            let vector = try Engine.Positions.backdatedPosition(
                of: .pluto, seenFrom: .earth, at: time, aberration: aberration)
            #expect(vector.time.tt < time.tt && vector.time.deltaTModel == .jplHorizons)
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Pluto.heliocentricState(at: vector.time)
            }
            let state = try Engine.Positions.geocentricState(of: .pluto, at: time, aberration: aberration)
            #expect(state.time.tt == time.tt && state.positionVector == SIMD3(vector.x, vector.y, vector.z))
            let ecliptic = try Engine.Positions.geocentricEclipticState(of: .pluto, at: time, aberration: aberration)
            #expect(ecliptic.state.time.tt == time.tt && ecliptic.longitude.isFinite && ecliptic.longitudeRate.isFinite)
            let equatorial = try Engine.Positions.equatorial(
                of: .pluto, at: time, from: .geocentric, equatorDate: .j2000, aberration: aberration)
            #expect(equatorial.rightAscension.isFinite && equatorial.declination.isFinite)
        }
        let horizontal = try Engine.Positions.horizontal(
            of: .pluto, at: time, from: ashevilleObserver, refraction: .none)
        #expect(horizontal.azimuth.isFinite && horizontal.altitude.isFinite)
        #expect(try Engine.Positions.angleFromSun(of: .pluto, at: time).isFinite)
        #expect(try Engine.Positions.pairLongitude(.pluto, .sun, at: time).isFinite)
        let elongation = try Engine.Positions.elongation(of: .pluto, at: time)
        #expect(elongation.elongation.isFinite && elongation.eclipticSeparation.isFinite)
    }

    @Test("The internal evaluator is confined to validated observations and the compiled source coverage")
    func internalEmissionGuard() throws {
        let observation = Engine.Time(tt: -766_525, deltaTModel: .jplHorizons)
        let retarded = observation.adding(days: -0.25)
        let state = try Engine.Pluto.heliocentricState(forLightTimeAt: retarded, observedAt: observation)
        #expect(state.time.tt == retarded.tt && state.time.deltaTModel == .jplHorizons)
        #expect(
            [state.x, state.y, state.z, state.vx, state.vy, state.vz].map(\.bitPattern) == [
                4_627_431_996_928_111_898, 4_631_104_392_175_455_840, 4_618_282_394_626_914_162,
                13_789_615_947_424_258_115, 4_560_118_899_743_259_915, 4_560_476_487_805_888_871,
            ])

        let sourceStartTDB = max(Engine.PlutoDE441.pluto.start, Engine.PlutoDE441.sun.start)
        _ = try Engine.Pluto.heliocentricState(
            forLightTimeAt: Engine.Time(tt: sourceStartTDB + 1, deltaTModel: .jplHorizons), observedAt: observation)
        for time in [
            Engine.Time(tt: sourceStartTDB - 1, deltaTModel: .jplHorizons),
            Engine.Time(tt: retarded.tt, deltaTModel: .espenakMeeus), observation.adding(days: 0.1), .invalid,
        ] {
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Pluto.heliocentricState(forLightTimeAt: time, observedAt: observation)
            }
        }
        for invalidObservation in [
            Engine.Time(tt: (-766_525.0).nextDown, deltaTModel: .jplHorizons),
            Engine.Time(tt: 766_525.0.nextUp, deltaTModel: .jplHorizons), .invalid,
        ] {
            #expect(throws: AstronomyError.badTime) {
                _ = try Engine.Pluto.heliocentricState(forLightTimeAt: retarded, observedAt: invalidObservation)
            }
        }
    }
}

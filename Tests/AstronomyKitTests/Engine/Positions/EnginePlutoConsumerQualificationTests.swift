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

    @Test("Observation endpoints expose the retarded-emission domain without changing the state range")
    func retardedDomain() throws {
        for tt in [-766_525.0, 766_525.0] {
            _ = try Engine.Positions.heliocentricPosition(
                of: .pluto, at: Engine.Time(tt: tt, deltaTModel: .jplHorizons))
        }
        for aberration in [Aberration.none, .corrected] {
            for tt in [-766_525.0, -766_524.9, (-766_525.0).nextDown, 766_525.0.nextUp, .nan, .infinity, -.infinity] {
                #expect(throws: AstronomyError.badTime) {
                    _ = try Engine.Positions.geocentricPosition(
                        of: .pluto, at: Engine.Time(tt: tt, deltaTModel: .jplHorizons), aberration: aberration)
                }
            }
            for tt in [-766_524.0, 766_524.0, 766_525.0] {
                let time = Engine.Time(tt: tt, deltaTModel: .jplHorizons)
                let result = try Engine.Positions.geocentricPosition(of: .pluto, at: time, aberration: aberration)
                #expect(result.time.tt == tt && result.length.isFinite)
            }
        }
    }
}

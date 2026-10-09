import Foundation
import Testing

@testable import AstronomyKit

@Suite("Independent native observer-event sources")
struct EngineObserverSourceTests {
    struct Fixture: Decodable {
        let angularToleranceArcminutes: Double
        let semidiameterComparisonDegrees: Double
        let rows: [Point]
        let semidiameters: [Semidiameter]
        let polar: [Polar]
    }
    struct Point: Decodable {
        let body: String
        let tt: Double
        let observer: [Double]
        let altitudeDegrees: Double
        let hourAngleHours: Double
        let tdbMinusUTSeconds: Double
        let dut1Seconds: Double?
    }
    struct Semidiameter: Decodable {
        let universalTime: String
        let semidiameterDegrees: Double
        let inferredRadiusKM: Double
    }
    struct Polar: Decodable {
        let tt: Double
        let altitudeDegrees: Double
        let distanceAU: Double
        let apparentICRFDeg: [Double]
    }

    static let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
    static func fixture() throws -> Fixture {
        try JSONDecoder().decode(
            Fixture.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/observer-event-data/reference-fixtures.json")))
    }

    static func write(_ value: Any, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["OBSERVER_EVENT_OUTPUT"] else { return }
        let url = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]).write(
            to: url.appendingPathComponent(name + ".json"))
    }

    @Test("Airless altitude and apparent hour angle against sixteen Horizons rows")
    func horizonPoints() throws {
        let fixture = try Self.fixture()
        #expect(fixture.rows.count == 16)
        var measurements: [[String: Any]] = []
        for row in fixture.rows {
            let body = try #require(CelestialBody.allCases.first { $0.name.lowercased() == row.body })
            // Horizons quantity 30 uses UT1 before 1962 and UTC thereafter. Quantity 49 supplies the latter's DUT1.
            let deltaT = row.tdbMinusUTSeconds - Engine.TDB.offsetSeconds(tt: row.tt) - (row.dut1Seconds ?? 0)
            let time = Engine.Time(ut: row.tt - deltaT / Engine.secondsPerDay, tt: row.tt, deltaTModel: .espenakMeeus)
            let observer = Observer(
                latitude: row.observer[1], longitude: row.observer[0], height: row.observer[2] * 1_000)
            let horizon = try Engine.Positions.horizontal(of: body, at: time, from: observer, refraction: .none)
            let hourAngle = try Engine.Events.hourAngle(of: body, at: time, from: observer)
            let altitudeError = abs(horizon.altitude - row.altitudeDegrees) * 60
            let hourAngleError = abs(Engine.longitudeOffset((hourAngle - row.hourAngleHours) * 15)) * 60
            #expect(altitudeError <= fixture.angularToleranceArcminutes)
            #expect(hourAngleError <= fixture.angularToleranceArcminutes)
            #expect(abs(horizon.altitude - (row.altitudeDegrees + 1)) * 60 > fixture.angularToleranceArcminutes)
            #expect(
                abs(Engine.longitudeOffset((hourAngle - row.hourAngleHours - 1) * 15)) * 60
                    > fixture.angularToleranceArcminutes)
            measurements.append([
                "body": row.body, "tt": row.tt, "ut": time.ut,
                "altitudeDegrees": horizon.altitude, "hourAngleHours": hourAngle,
                "altitudeErrorArcminutes": altitudeError, "hourAngleErrorArcminutes": hourAngleError,
            ])
        }
        try Self.write(measurements, name: "points")
    }

    @Test("USNO optical semidiameters exclude the nominal-radius control at three dates")
    func opticalSemidiameters() throws {
        let fixture = try Self.fixture()
        var measurements: [[String: Any]] = []
        for row in fixture.semidiameters {
            let reference = IndependentReferenceDate.universal(row.universalTime, deltaTModel: .espenakMeeus)
            let time = Engine.Time(ut: reference.universalTime, deltaTModel: .espenakMeeus)
            let equatorial = try Engine.Positions.equatorial(
                of: .sun, at: time, from: Observer(latitude: 0, longitude: 0), equatorDate: .ofDate,
                aberration: .corrected)
            let optical = asin(696_000 / Engine.kilometersPerAU / equatorial.distance) * Engine.degreesPerRadian
            let nominal = asin(695_700 / Engine.kilometersPerAU / equatorial.distance) * Engine.degreesPerRadian
            #expect(abs(optical - row.semidiameterDegrees) <= fixture.semidiameterComparisonDegrees)
            #expect(abs(nominal - row.semidiameterDegrees) > 100 * fixture.semidiameterComparisonDegrees)
            #expect(abs(row.inferredRadiusKM - 696_000) < 2)
            measurements.append([
                "universalTime": row.universalTime, "opticalDegrees": optical,
                "nominalDegrees": nominal, "sourceDegrees": row.semidiameterDegrees,
                "opticalResidualDegrees": optical - row.semidiameterDegrees,
            ])
        }
        try Self.write(measurements, name: "semidiameters")
    }

    @Test("Polar airless source discriminator keeps trajectory and limb convention separate")
    func polarDiscriminator() throws {
        let fixture = try Self.fixture()
        let site = Observer(latitude: -90, longitude: 0)
        var measurements: [[String: Any]] = []
        for row in fixture.polar {
            // Consistent modeled UT/TT keeps the light-time path on this TT. At the exact pole the spin angle does not change altitude.
            let time = Engine.Time(tt: row.tt, deltaTModel: .espenakMeeus)
            let eq = try Engine.Positions.equatorial(
                of: .sun, at: time, from: site, equatorDate: .j2000, aberration: .corrected)
            let horizon = try Engine.Positions.horizontal(of: .sun, at: time, from: site, refraction: .none)
            let sourceNominal =
                row.altitudeDegrees + asin(695_700 / Engine.kilometersPerAU / row.distanceAU) * Engine.degreesPerRadian
                + 34.0 / 60
            let sourceOptical =
                row.altitudeDegrees + asin(696_000 / Engine.kilometersPerAU / row.distanceAU) * Engine.degreesPerRadian
                + 34.0 / 60
            #expect(abs(horizon.altitude - row.altitudeDegrees) * 60 <= fixture.angularToleranceArcminutes)
            measurements.append([
                "tt": row.tt, "nativeAltitudeDegrees": horizon.altitude,
                "sourceAltitudeDegrees": row.altitudeDegrees, "nativeDistanceAU": eq.distance,
                "nativeApparentICRFDeg": [eq.rightAscension * 15, eq.declination],
                "sourceNominalResidualDegrees": sourceNominal, "sourceOpticalResidualDegrees": sourceOptical,
            ])
        }
        try Self.write(measurements, name: "polar")
    }
}

import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native Moon event qualification")
struct EngineMoonEventQualificationTests {
    @Test("The direct-source event oracle matches independently summed midpoint states")
    func directOracle() throws {
        let fixture = try MoonEventQualification.load()
        #expect(fixture.windows.count == 20)
        for record in fixture.records {
            let tdb = fixture.sourceStartTDB + Double(record.index) * 4 + 2
            let actual = try fixture.source(tdb: tdb)
            for axis in 0..<3 {
                #expect(abs(actual.position[axis] - record.midpointPositionKm[axis]) < 1e-8)
                #expect(abs(actual.velocity[axis] - record.midpointVelocityKmPerTDBDay[axis]) < 1e-8)
            }
        }
    }
}

extension EngineMoonEventQualificationTests {
    typealias Harness = MoonEventQualification

    static func write(_ rows: [[String: Any]], environment: String) throws {
        if let path = ProcessInfo.processInfo.environment[environment] {
            try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]).write(
                to: URL(fileURLWithPath: path))
        }
    }

    @Test("The forward oracle evaluates non-midpoint polynomial values and rates")
    func polynomialOracle() throws {
        let record = Harness.Record(
            index: 0, coefficientsKm: [[1, 2, 3], [0, 0, 0], [2, -1, 0]], midpointPositionKm: [],
            midpointVelocityKmPerTDBDay: [])
        let fixture = Harness(sourceStartTDB: 0, windows: [], records: [record])
        for x in [-0.75, 0.25, 0.875] {
            let actual = try fixture.source(tdb: (x + 1) * 2)
            #expect(abs(actual.position.x - (1 + 2 * x + 3 * (2 * x * x - 1))) < 1e-13)
            #expect(abs(actual.velocity.x - (2 + 12 * x) / 2) < 1e-13)
            #expect(actual.position.y == 0 && actual.velocity.y == 0)
            #expect(actual.position.z == 2 - x && actual.velocity.z == -0.5)
        }
    }

    @Test("Native event roots retain the established published time and distance allowances")
    func publishedRoots() throws {
        let fixture = try Harness.load()
        var rows: [[String: Any]] = []
        func check(
            _ event: Harness.Event, tt: Double, seconds: Double, distance: Double? = nil,
            distanceAllowance: Double? = nil, meanNode: Bool = false
        ) throws {
            let roots = try fixture.roots(event, start: tt - 2, end: tt + 2, direct: false, meanNode: meanNode)
            #expect(roots.count == 1)
            let actual = try #require(roots.first)
            let residual = (actual.tt - tt) * Engine.secondsPerDay
            #expect(abs(residual) <= seconds, "\(event.rawValue) TT \(tt): \(residual) s")
            var row: [String: Any] = [
                "event": event.rawValue, "referenceTT": tt, "nativeTT": actual.tt, "residualSeconds": residual,
                "timeAllowanceSeconds": seconds, "meanNode": meanNode,
            ]
            if let distance, let distanceAllowance {
                #expect(abs(actual.distanceKm - distance) <= distanceAllowance)
                row["distanceResidualKm"] = actual.distanceKm - distance
                row["distanceAllowanceKm"] = distanceAllowance
            }
            rows.append(row)
        }
        let references = IndependentReferenceArchive.shared
        #expect(
            references.lunarPhases.count == 12 && references.lunarNodes.count == 6 && references.lunarApsides.count == 6
        )
        for reference in references.lunarPhases {
            try check(
                try #require(Harness.Event(rawValue: reference.phase)),
                tt: IndependentReferenceDate.engine(reference.sourceTime).tt, seconds: reference.toleranceSeconds)
        }
        for reference in references.lunarNodes {
            try check(
                try #require(Harness.Event(rawValue: reference.kind)),
                tt: IndependentReferenceDate.civil(reference.utc).terrestrialTime,
                seconds: reference.timeToleranceSeconds)
        }
        for reference in references.lunarApsides {
            try check(
                try #require(Harness.Event(rawValue: reference.kind)),
                tt: IndependentReferenceDate.civil(reference.utc).terrestrialTime,
                seconds: reference.timeToleranceSeconds, distance: reference.distanceKM,
                distanceAllowance: reference.distanceToleranceKM)
        }
        // Preserve the geometric mean-ecliptic definition of BundledEphemerisTests' independent 1903 cases.
        try check(.pericenter, tt: 2_416_319.984182304 - 2_451_545, seconds: 60)
        try check(.ascending, tt: 2_416_324.69497546 - 2_451_545, seconds: 60, meanNode: true)
        let label = "2100-01-18T12:35:00.000Z"
        let sourceTime = IndependentReferenceDate.engine(label)
        #expect(
            abs(sourceTime.tt - IndependentReferenceDate.civil(label).terrestrialTime) * Engine.secondsPerDay > 90)
        try Self.write(rows, environment: "MOON_PUBLISHED_EVENT_OUTPUT")
    }

    @Test("Frozen full-span and transition windows pair actual native and source event roots")
    func sourceRoots() throws {
        let fixture = try Harness.load()
        var rows: [[String: Any]] = []
        for window in fixture.windows {
            for event in Harness.Event.allCases {
                let direct = try fixture.roots(event, start: window.startTT, end: window.endTT, direct: true)
                let native: [Harness.Root]
                do {
                    native = try fixture.productionRoots(event, matching: direct)
                } catch {
                    Issue.record("\(window.id) \(event.rawValue): \(error)")
                    throw error
                }
                #expect(!direct.isEmpty && native.count == direct.count, "\(window.id) \(event.rawValue)")
                for (a, b) in zip(direct, native) {
                    let residual = (b.tt - a.tt) * Engine.secondsPerDay
                    #expect(residual.isFinite)
                    for (root, isDirect) in [(a, true), (b, false)] {
                        let before = try fixture.value(event, at: Harness.time(root.tt - 1.0 / 1440), direct: isDirect)
                        let after = try fixture.value(event, at: Harness.time(root.tt + 1.0 / 1440), direct: isDirect)
                        #expect(before < 0 && after > 0, "\(window.id) \(event.rawValue) \(root.tt)")
                    }
                    rows.append([
                        "window": window.id, "event": event.rawValue, "sourceTT": a.tt, "nativeTT": b.tt,
                        "residualSeconds": residual, "distanceResidualKm": b.distanceKm - a.distanceKm,
                    ])
                }
                if window.id.hasPrefix("blend") || ["uniform-00", "uniform-16", "source-segment"].contains(window.id) {
                    for coarse in [direct] {
                        let fine = try fixture.roots(
                            event, start: window.startTT, end: window.endTT, direct: true, step: 0.25)
                        #expect(fine.count == coarse.count)
                        for (a, b) in zip(coarse, fine) {
                            // Numerical search agreement only; this is not an event-accuracy allowance.
                            #expect(abs(a.tt - b.tt) * Engine.secondsPerDay < 0.01)
                        }
                    }
                }
            }
        }
        try Self.write(rows, environment: "MOON_SOURCE_EVENT_OUTPUT")
    }

    @Test("Transition state residuals retain existing angular and distance checks")
    func transitionStates() throws {
        let fixture = try Harness.load()
        var rows: [[String: Any]] = []
        for boundary in [-36_556.5, -36_524.5, 47_846.5, 47_878.5, -11_112.5] {
            for offset in [-0.01, -0.001, 0, 0.001, 0.01] {
                let time = Harness.time(boundary + offset)
                let source = try fixture.state(at: time, direct: true)
                let native = try fixture.state(at: time, direct: false)
                func vector(_ p: SIMD3<Double>) -> Engine.Vector<Engine.EQJ> {
                    Engine.Vector(
                        x: p.x / Engine.kilometersPerAU, y: p.y / Engine.kilometersPerAU,
                        z: p.z / Engine.kilometersPerAU, time: time)
                }
                let angle = try vector(source.position).angle(to: vector(native.position)) * 60
                let distance = abs(
                    (source.position * source.position).sum().squareRoot()
                        - (native.position * native.position).sum().squareRoot())
                let dv = native.velocity - source.velocity
                let rate = (dv * dv).sum().squareRoot()
                #expect(angle <= toleranceArcminutes)
                #expect(distance <= EngineMoonHorizonsTests.distanceAllowanceKm)
                #expect(rate.isFinite)
                rows.append([
                    "boundaryTT": boundary, "offsetDays": offset, "angleArcminutes": angle, "distanceKm": distance,
                    "velocityResidualKmPerTTDay": rate,
                ])
            }
        }
        try Self.write(rows, environment: "MOON_TRANSITION_OUTPUT")
    }
}

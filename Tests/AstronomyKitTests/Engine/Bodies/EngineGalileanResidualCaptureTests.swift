import Foundation
import Testing

@testable import AstronomyKit

@Suite("Engine.GalileanResidualCapture")
struct EngineGalileanResidualCaptureTests {
    @Test("Capture all archived Galilean epochs with raw state and clock metadata")
    func capture() throws {
        typealias Moons = Engine.JupiterMoons
        let names: [(String, Moons.Moon, Int)] = [
            ("io", .io, 501), ("europa", .europa, 502),
            ("ganymede", .ganymede, 503), ("callisto", .callisto, 504),
        ]
        let references = IndependentReferenceArchive.shared.vectors.filter { $0.origin == "jupiter" }
        #expect(references.count == 104)
        var rows: [[String: Any]] = []
        for (name, moon, target) in names {
            let selected = references.filter { $0.body == name }
            #expect(selected.count == 26)
            for reference in selected {
                let tdb = reference.julianDateTDB - 2_451_545
                var tt = tdb
                for _ in 0..<3 { tt = tdb - Engine.TDB.offsetSeconds(tt: tt) / Engine.secondsPerDay }
                let clock = Engine.TDB.offsetAndRate(tt: tt)
                let state = try Moons.state(of: moon, at: PlanetTestSupport.time(tt: tt))
                #expect(state.time.tt == tt)
                #expect(abs((tt - tdb) + clock.offsetSeconds / Engine.secondsPerDay) < 1e-11)
                rows.append([
                    "body": name, "target": target, "center": 599, "frame": "EQJ", "epochScale": "TDB",
                    "julianDateTDB": reference.julianDateTDB, "ttDays": tt,
                    "tdbMinusTTSeconds": clock.offsetSeconds, "tdbPerTTRate": clock.rate,
                    "positionAU": [state.x, state.y, state.z],
                    "keplerianVelocityAUPerTTDay": [state.vx, state.vy, state.vz],
                ])
            }
        }
        if let path = ProcessInfo.processInfo.environment["GALILEAN_RESIDUAL_OUTPUT"] {
            try JSONSerialization.data(
                withJSONObject: ["schemaVersion": 1, "rows": rows], options: [.prettyPrinted, .sortedKeys]
            ).write(to: URL(fileURLWithPath: path), options: .atomic)
        }
    }
}

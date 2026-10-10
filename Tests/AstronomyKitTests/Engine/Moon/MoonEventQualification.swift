import Foundation

@testable import AstronomyKit

/// Test-only event functions and a direct DE441 oracle; production searches belong to #92.
struct MoonEventQualification: Decodable {
    struct Window: Decodable {
        let id: String
        let startTT: Double
        let endTT: Double
    }

    struct Record: Decodable {
        let index: Int
        let coefficientsKm: [[Double]]
        let midpointPositionKm: [Double]
        let midpointVelocityKmPerTDBDay: [Double]
    }

    enum Event: String, CaseIterable, Codable {
        case new, firstQuarter, full, lastQuarter, ascending, descending, pericenter, apocenter

        var phase: Double? {
            switch self {
            case .new: 0
            case .firstQuarter: 90
            case .full: 180
            case .lastQuarter: 270
            default: nil
            }
        }
    }

    struct Root: Codable {
        let event: Event
        let tt: Double
        let distanceKm: Double
    }

    enum Failure: Error { case missingRecord, missingRoot }

    let sourceStartTDB: Double
    let windows: [Window]
    let records: [Record]

    static func load() throws -> Self {
        let root = (0..<5).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
        return try JSONDecoder().decode(
            Self.self,
            from: Data(contentsOf: root.appendingPathComponent("Scripts/moon-data/de441-event-fixtures.json")))
    }

    /// Forward Chebyshev sums, separate from the compact evaluator's reconstructed Clenshaw recurrence.
    func source(tdb: Double) throws -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        let index = Int(floor((tdb - sourceStartTDB) / 4))
        guard let record = records.first(where: { $0.index == index }) else { throw Failure.missingRecord }
        let x = (tdb - sourceStartTDB - Double(index) * 4) / 2 - 1
        var position = SIMD3<Double>()
        var velocity = SIMD3<Double>()
        for axis in 0..<3 {
            let c = record.coefficientsKm[axis]
            var (t0, t1, d0, d1) = (1.0, x, 0.0, 1.0)
            position[axis] = c[0] + c[1] * x
            velocity[axis] = c[1]
            for k in 2..<c.count {
                let t = 2 * x * t1 - t0
                let d = 2 * t1 + 2 * x * d1 - d0
                position[axis] += c[k] * t
                velocity[axis] += c[k] * d
                (t0, t1, d0, d1) = (t1, t, d1, d)
            }
        }
        return (position, velocity / 2)
    }

    func state(at time: Engine.Time, direct: Bool) throws -> (position: SIMD3<Double>, velocity: SIMD3<Double>) {
        if direct {
            let value = try source(tdb: time.tt + Engine.TDB.offsetSeconds(tt: time.tt) / Engine.secondsPerDay)
            return (
                Engine.FrameBias.icrsToEqj.apply(to: value.position),
                Engine.FrameBias.icrsToEqj.apply(to: value.velocity * Engine.TDB.rate(tt: time.tt))
            )
        }
        let value = try Engine.Moon.geocentricState(at: time)
        return (
            SIMD3(value.x, value.y, value.z) * Engine.kilometersPerAU,
            SIMD3(value.vx, value.vy, value.vz) * Engine.kilometersPerAU
        )
    }

    func value(_ event: Event, at time: Engine.Time, direct: Bool, meanNode: Bool = false) throws -> Double {
        if let phase = event.phase {
            let moon = Engine.Ecliptic(
                try Engine.LightTravel.correct(at: time) { backdated in
                    let state = try state(at: backdated, direct: direct)
                    let position = state.position / Engine.kilometersPerAU
                    return Engine.Vector(x: position.x, y: position.y, z: position.z, time: backdated)
                }
            ).longitude
            let sun = try Engine.Positions.sunPosition(at: time).longitude
            return Engine.longitudeOffset(moon - sun - phase)
        }
        let current = try state(at: time, direct: direct)
        if event == .pericenter || event == .apocenter {
            let slope =
                (current.position * current.velocity).sum()
                / (current.position * current.position).sum().squareRoot()
            return event == .pericenter ? slope : -slope
        }
        if meanNode {
            let mean = Engine.Moon.meanEquatorToEcliptic(tt: time.tt).apply(
                to: Engine.Precession.rotation(tt: time.tt).apply(to: current.position))
            return event == .ascending ? mean.z : -mean.z
        }
        let position = current.position / Engine.kilometersPerAU
        let vector = Engine.Vector<Engine.EQJ>(x: position.x, y: position.y, z: position.z, time: time)
        let angles = Engine.Moon.eclipticAngles(Engine.FrameRotation.eqjToEct(time).apply(to: vector))
        return event == .ascending ? angles.latitude : -angles.latitude
    }

    static func time(_ tt: Double) -> Engine.Time { Engine.Time(tt: tt, deltaTModel: .espenakMeeus) }

    /// Fixed half-day discovery brackets followed by the existing native root solver at 1 ms tolerance.
    func roots(
        _ event: Event, start: Double, end: Double, direct: Bool, step: Double = 0.5, meanNode: Bool = false
    ) throws -> [Root] {
        var result: [Root] = []
        var a = start
        var fa = try value(event, at: Self.time(a), direct: direct, meanNode: meanNode)
        while a < end {
            let b = min(end, a + step)
            let fb = try value(event, at: Self.time(b), direct: direct, meanNode: meanNode)
            // A phase wrap from +180 to -180 is not a quarter crossing.
            if fa <= 0 && fb >= 0 && (fa < 0 || fb > 0) && (event.phase == nil || fb - fa < 180) {
                guard
                    let time = try Engine.Search.ascendingRoot(
                        from: Self.time(a), to: Self.time(b), toleranceSeconds: 0.001,
                        { time in
                            try value(event, at: time, direct: direct, meanNode: meanNode)
                        })
                else { throw Failure.missingRoot }
                if result.last.map({ abs($0.tt - time.tt) > 1e-7 }) ?? true {
                    let position = try state(at: time, direct: direct).position
                    result.append(Root(event: event, tt: time.tt, distanceKm: (position * position).sum().squareRoot()))
                }
            }
            (a, fa) = (b, fb)
        }
        return result
    }

    /// Production event discovery around each direct-source root, with every probe kept inside the accepted range.
    func productionRoots(_ event: Event, matching sourceRoots: [Root]) throws -> [Root] {
        var result: [Root] = []
        func append(_ time: Engine.Time) throws {
            let distance = try Engine.Moon.distance(at: time) * Engine.kilometersPerAU
            result.append(Root(event: event, tt: time.tt, distanceKm: distance))
        }

        if let phase = event.phase {
            for source in sourceRoots {
                let start = max(-Engine.acceptedTTDays, source.tt - 1)
                guard
                    let time = try Engine.Events.searchMoonPhase(
                        phase, after: Self.time(start), limitDays: min(2, Engine.acceptedTTDays - start))
                else { throw Failure.missingRoot }
                try append(time)
            }
            return result
        }

        if event == .ascending || event == .descending {
            for source in sourceRoots {
                let start = max(-Engine.acceptedTTDays, source.tt - 9.9)
                let node = try Engine.Events.searchLunarNode(after: Self.time(start))
                guard (event == .ascending) == (node.kind == .ascending) else { throw Failure.missingRoot }
                try append(node.time)
            }
            return result
        }

        for source in sourceRoots {
            let start = max(-Engine.acceptedTTDays, source.tt - 4.9)
            let apsis = try Engine.Events.searchLunarApsis(after: Self.time(start))
            guard (event == .pericenter) == (apsis.kind == .pericenter) else { throw Failure.missingRoot }
            try append(apsis.time)
        }
        return result
    }
}

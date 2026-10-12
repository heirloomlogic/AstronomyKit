import Foundation

extension Engine {
    /// Unwired DE-backed source components for the issue 248 planet migration.
    enum PlanetDE441 {}
}

extension Engine.PlanetDE441 {
    /// The shared DE441 Sun table already used by Saturn. Keeping one copy avoids changing the current Saturn route in this foundation link.
    static let sun = direct(Engine.SaturnEphemeris.sun)
    private static let saturnBarycenter = direct(Engine.SaturnEphemeris.barycenter)
    private static let saturnOffset = direct(Engine.SaturnEphemeris.offset)

    private static func direct(_ table: Engine.SaturnEphemeris.Table) -> Engine.DirectChebyshevTable {
        Engine.DirectChebyshevTable(
            start: table.start, days: table.days, recordCount: table.recordCount,
            coefficientCount: table.coefficientCount, scalarBytes: table.scalarBytes, data: table.data)
    }

    /// Generated tables owned by the issue 248 generator. Saturn retains its separately qualified tables until runtime integration.
    static var components: [String: Engine.DirectChebyshevTable] {
        [
            "mercuryBarycenter": mercuryBarycenter,
            "venusBarycenter": venusBarycenter,
            "earthBarycenter": earthBarycenter,
            "earthOffset": earthOffset,
            "marsBarycenter": marsBarycenter,
            "jupiterBarycenter": jupiterBarycenter,
            "jupiterOffset": jupiterOffset,
            "uranusBarycenter": uranusBarycenter,
            "uranusOffset": uranusOffset,
            "neptuneBarycenter": neptuneBarycenter,
            "neptuneOffset": neptuneOffset,
            "sun": sun,
        ]
    }

    /// Composes a source state without changing the public planet route. Position is in AU on EQJ axes and velocity is its derivative per TT day.
    static func state(
        of planet: Engine.Planet, tt: Double, physicalCenter: Bool
    ) -> (position: SIMD3<Double>, velocity: SIMD3<Double>)? {
        guard tt.isFinite else { return nil }
        let conversion = Engine.TDB.offsetAndRate(tt: tt)
        let tdb = tt + conversion.offsetSeconds / Engine.secondsPerDay
        guard let tables = tables(of: planet), let barycenter = tables.barycenter.evaluate(tdb: tdb),
            let solar = sun.evaluate(tdb: tdb)
        else { return nil }
        var position = barycenter.position - solar.position
        var velocity = barycenter.velocity - solar.velocity
        if physicalCenter, let offsetTable = tables.offset {
            guard let offset = offsetTable.evaluate(tdb: tdb) else { return nil }
            position += offset.position
            velocity += offset.velocity
        }
        let bias = Engine.FrameBias.icrsToEqj
        return (
            bias.apply(to: position / Engine.kilometersPerAU),
            bias.apply(to: velocity * conversion.rate / Engine.kilometersPerAU)
        )
    }

    private static func tables(
        of planet: Engine.Planet
    ) -> (barycenter: Engine.DirectChebyshevTable, offset: Engine.DirectChebyshevTable?)? {
        switch planet {
        case .mercury: (mercuryBarycenter, nil)
        case .venus: (venusBarycenter, nil)
        case .earth: (earthBarycenter, earthOffset)
        case .mars: (marsBarycenter, nil)
        case .jupiter: (jupiterBarycenter, jupiterOffset)
        case .saturn: (saturnBarycenter, saturnOffset)
        case .uranus: (uranusBarycenter, uranusOffset)
        case .neptune: (neptuneBarycenter, neptuneOffset)
        }
    }
}

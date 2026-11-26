//
//  EngineLunarNode.swift
//  AstronomyKit
//
//  Pure-Swift lunar node crossing search matching Astronomy_SearchMoonNode
//  and Astronomy_NextMoonNode (preserving finite/step-advance and accepted-range guards).
//

enum EngineLunarNode {
    private static let stepDays = 10.0

    static func searchNode(after startTime: AstroTime) throws -> LunarNode {
        var time1 = startTime
        var eclip1 = try EnginePositions.eclipticGeoMoon(at: time1)

        while true {
            let time2 = time1.addingDays(stepDays)
            guard time1.universalTime < time2.universalTime else {
                throw AstronomyError.badTime
            }

            let eclip2 = try EnginePositions.eclipticGeoMoon(at: time2)

            if eclip1.latitude * eclip2.latitude <= 0.0 {
                let kind: NodeKind = (eclip2.latitude > eclip1.latitude) ? .ascending : .descending
                let sign: Double = (kind == .ascending) ? 1.0 : -1.0
                let crossing = try EngineSearch.find(t1: time1, t2: time2, dtToleranceSeconds: 1.0) { t in
                    let eclip = try EnginePositions.eclipticGeoMoon(at: t)
                    return eclip.latitude * sign
                }
                return LunarNode(kind: kind, time: crossing)
            }

            time1 = time2
            eclip1 = eclip2
        }
    }

    static func nextNode(after prevNode: LunarNode) throws -> LunarNode {
        let next = try searchNode(after: prevNode.time.addingDays(stepDays))
        guard next.kind != prevNode.kind else {
            throw AstronomyError.internalError
        }
        return next
    }
}

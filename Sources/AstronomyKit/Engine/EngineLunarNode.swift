//
//  EngineLunarNode.swift
//  AstronomyKit
//
//  Pure-Swift lunar node crossing search matching Astronomy_SearchMoonNode
//  and Astronomy_NextMoonNode (preserving finite/step-advance and accepted-range guards).
//

import CLibAstronomy

enum EngineLunarNode {
    private static let stepDays = 10.0

    static func searchNode(after startTime: AstroTime) throws -> LunarNode {
        var time1 = startTime
        var eclip1 = Astronomy_EclipticGeoMoon(time1.raw)
        if let error = AstronomyError(status: eclip1.status) {
            throw error
        }

        while true {
            let time2 = time1.addingDays(stepDays)
            guard time1.universalTime < time2.universalTime else {
                throw AstronomyError.badTime
            }

            let eclip2 = Astronomy_EclipticGeoMoon(time2.raw)
            if let error = AstronomyError(status: eclip2.status) {
                throw error
            }

            if eclip1.lat * eclip2.lat <= 0.0 {
                let kind: NodeKind = (eclip2.lat > eclip1.lat) ? .ascending : .descending
                let sign: Double = (kind == .ascending) ? 1.0 : -1.0
                let crossing = try EngineSearch.find(t1: time1, t2: time2, dtToleranceSeconds: 1.0) { t in
                    let eclip = Astronomy_EclipticGeoMoon(t.raw)
                    if let error = AstronomyError(status: eclip.status) {
                        throw error
                    }
                    return eclip.lat * sign
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

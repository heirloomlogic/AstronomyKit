import Foundation

@testable import AstronomyKit

let site = Observer(latitude: 16.85, longitude: -99 - 55 / 60, height: 3)
let sourceUT = -2061.8395543981483
let event = try Engine.Events.searchLocalSolarEclipse(
    after: Engine.Time(ut: sourceUT - 10, deltaTModel: .espenakMeeus), from: site)
func value(_ time: Engine.Time, _ which: Int) throws -> Double {
    let g = try Engine.Events.localSolarGeometry(at: time, from: site)
    if which == 0 { return g.axisDistanceKilometers }
    if which == 1 { return -g.exteriorMargin / (2 * g.discs.sunRadiusRadians) }
    if which == 2 { return g.discs.separationRadians }
    return -g.discs.obscuration
}
// Diagnostic only: distinguish the retained axis minimum from published maximum definitions.
var rows: [[String: Any]] = []
for mode in 0..<4 {
    let candidate = try Engine.Search.ascendingRoot(
        from: event.physicalPeak.adding(days: -0.01), to: event.physicalPeak.adding(days: 0.01), toleranceSeconds: 0.001
    ) { t in try value(t.adding(days: 1 / 86400), mode) - value(t.adding(days: -1 / 86400), mode) }
    guard let root = candidate else { throw AstronomyError.searchFailure }
    rows.append([
        "mode": mode, "sourceUT": sourceUT, "ut": root.ut, "tt": root.tt,
        "residualSeconds": (root.ut - sourceUT) * 86400, "magnitude": try -value(root, 1), "area": try -value(root, 3),
    ])
}
print(
    String(
        decoding: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
        as: UTF8.self))

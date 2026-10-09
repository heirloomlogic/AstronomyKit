import Foundation

@testable import AstronomyKit

let au = Engine.kilometersPerAU
var rows: [[String: Any]] = []
for tt in [-2061.783027, -2061.7840335648148, -2061.7805613425926, -4837.703993055556] {
    let t = Engine.Time(tt: tt, deltaTModel: .espenakMeeus)
    let s = try Engine.Positions.geocentricPosition(of: .sun, at: t, aberration: .corrected)
    let m = try Engine.Moon.geocentricPosition(at: t)
    let rot = Engine.FrameRotation.eqjToEqd(t)
    let sd = rot.apply(to: s)
    let md = rot.apply(to: m)
    rows.append([
        "tt": tt, "sun": [s.x * au, s.y * au, s.z * au], "moon": [m.x * au, m.y * au, m.z * au],
        "sunEQD": [sd.x * au, sd.y * au, sd.z * au], "moonEQD": [md.x * au, md.y * au, md.z * au],
    ])
}
print(
    String(
        decoding: try JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]),
        as: UTF8.self))

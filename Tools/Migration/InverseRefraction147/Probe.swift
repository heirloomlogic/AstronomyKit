import AstronomyKit
import Foundation

let arguments = CommandLine.arguments
let mode: Refraction
switch arguments[1] {
case "none": mode = .none
case "normal": mode = .normal
case "jplHorizons": mode = .jplHorizons
default: fatalError("unknown mode")
}
let altitude: Double
switch arguments[2] {
case "nan": altitude = .nan
case "inf": altitude = .infinity
case "-inf": altitude = -.infinity
case "90.nextDown": altitude = Double(90).nextDown
case "90.nextUp": altitude = Double(90).nextUp
case "-90.nextDown": altitude = Double(-90).nextDown
case "-90.nextUp": altitude = Double(-90).nextUp
default: altitude = Double(arguments[2])!
}
let model: DeltaTModel = arguments[4] == "espenakMeeus" ? .espenakMeeus : .jplHorizons
let time = AstroTime(ut: 10_000, deltaTModel: model)
func bits(_ value: Double) -> String { String(value.bitPattern, radix: 16) }
var packet: [String: Any] = [
    "mode": arguments[1], "input": arguments[2], "route": arguments[3], "model": arguments[4],
    "inputBits": bits(altitude), "utBits": bits(time.universalTime), "ttBits": bits(time.terrestrialTime),
]
FileHandle.standardOutput.write(Data("entered\n".utf8))
switch arguments[3] {
case "direct":
    let correction = mode.inverseRefractionAngle(at: altitude)
    packet["correctionBits"] = bits(correction)
    packet["finite"] = correction.isFinite
case "horizon":
    let vector = Vector3D.from(horizon: Spherical(latitude: altitude, longitude: 123, distance: 2), at: time, refraction: mode)
    packet["vectorBits"] = [bits(vector.x), bits(vector.y), bits(vector.z)]
    packet["finite"] = vector.x.isFinite && vector.y.isFinite && vector.z.isFinite
    packet["timePreserved"] = vector.time == time
default: fatalError("unknown route")
}
FileHandle.standardOutput.write(try JSONSerialization.data(withJSONObject: packet, options: [.sortedKeys]))
FileHandle.standardOutput.write(Data("\n".utf8))

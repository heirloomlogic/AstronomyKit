// Maintained from the #369 diagnostic; requires a built AstrologyKit checkout.
// Usage: probe <frozen-facts-directory> <output.json>
import AstronomyKit
import Foundation

@testable import AstrologyKit

struct ElectionAstronomyProbeTests {
    func measureIndependentRoots() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var results: [[String: Any]] = []
        let dateRotation = ProcessInfo.processInfo.environment["ASTROLOGY_PROBE_DATE_ROTATION"] == "1"
        func signed(_ x: Double) -> Double {
            var y = x.truncatingRemainder(dividingBy: 360)
            if y > 180 { y -= 360 }
            if y < -180 { y += 360 }
            return y
        }
        for index in 1...24 {
            let id = String(format: "A%02d", index)
            let url = root.appendingPathComponent("\(id).json")
            let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            let oracle = fixture["oracleOutput"] as! [String: Any]
            let query = oracle["query"] as! [String: Any]
            let observer = Observer(latitude: query["latitudeDegrees"] as! Double, longitude: query["longitudeDegrees"] as! Double)
            for (eventIndex, event) in (oracle["events"] as! [[String: Any]]).enumerated() {
                let kind = event["kind"] as! String
                let referenceString = event["instant"] as! String
                let reference = formatter.date(from: referenceString)!
                let bodies = event["bodies"] as? [String] ?? []
                func position(_ body: String, _ date: Date) throws -> (longitude: Double, speed: Double) {
                    let planet = Planet.allCases.first { $0.rawValue.lowercased() == body }!
                    if !dateRotation || planet == .sun || planet == .moon {
                        return try probeRequire(ElectionFactBuilder.observePosition(planet, at: AstroTime(date), observer: observer))
                    }
                    let celestial = GeocentricCalculations.celestialBody(for: planet)!
                    func rotatedLongitude(_ at: Date) throws -> Double {
                        let time = AstroTime(at)
                        let equatorial = try celestial.equatorial(at: time, equatorDate: .ofDate)
                        let ra = equatorial.rightAscension * .pi / 12
                        let dec = equatorial.declination * .pi / 180
                        let vector = Vector3D(x: cos(dec)*cos(ra), y: cos(dec)*sin(ra), z: sin(dec), time: time)
                        let rotation = try RotationMatrix.equatorialOfDateToEclipticOfDate(at:time)
                        let ecliptic = try vector.rotated(by:rotation)
                        let degrees = atan2(ecliptic.y,ecliptic.x) * 180 / .pi
                        return degrees < 0 ? degrees + 360 : degrees
                    }
                    let width = AstronomicalConstants.speedDifferenceWidthDays
                    let speed = try PlanetarySpeed.dailyMotion(before:rotatedLongitude(date.addingTimeInterval(-width*43200)),after:rotatedLongitude(date.addingTimeInterval(width*43200)),widthDays:width)
                    return (try rotatedLongitude(date),speed)
                }
                func residual(_ seconds: Double) throws -> Double {
                    let date = reference.addingTimeInterval(seconds)
                    let time = AstroTime(date)
                    switch kind {
                    case "station": return try position(bodies[0], date).speed
                    case "aspect", "phaseBoundary", "solarBandCrossing":
                        return try signed(position(bodies[0], date).longitude - position(bodies[1], date).longitude - (event["signedBranchDegrees"] as! Double))
                    case "signIngress": return try signed(position(bodies[0], date).longitude - (event["targetDegrees"] as! Double))
                    case "ascendantIngress": return signed(HouseCalculations.calculateAngles(at: time, from: observer).ascendant)
                    case "midheavenIngress": return signed(HouseCalculations.calculateAngles(at: time, from: observer).midheaven)
                    case "houseCrossing":
                        return try signed(position("moon", date).longitude - HouseCalculations.calculateHouseCusps(at: time, from: observer).cusps[1])
                    case "angularBandCrossing": return try signed(position("mars", date).longitude - HouseCalculations.calculateAngles(at: time, from: observer).ascendant - 5)
                    default: fatalError(kind)
                    }
                }
                let referenceResidual = try residual(0)
                var width = 10.0
                while try residual(-width) * residual(width) > 0 && width < 86400 { width *= 2 }
                var lower = -width
                var upper = width
                var lowValue = try residual(lower)
                let highValue = try residual(upper)
                if lowValue * highValue > 0 {
                    results.append(["caseID":id,"eventIndex":eventIndex,"kind":kind,"error":"no local sign bracket","referenceResidual":referenceResidual])
                    continue
                }
                for _ in 0..<60 {
                    if upper - lower < 0.001 { break }
                    let middle = (lower + upper)/2
                    let value = try residual(middle)
                    if lowValue * value <= 0 { upper = middle } else { lower = middle; lowValue = value }
                }
                let offset = (lower + upper)/2
                let local = try residual(offset)
                let row: [String:Any] = ["identity":event,"caseID":id,"eventIndex":eventIndex,"kind":kind,"bodies":bodies,"referenceInstant":referenceString,"productionInstant":formatter.string(from:reference.addingTimeInterval(offset)),"signedTimeErrorSeconds":offset,"absoluteTimeErrorSeconds":abs(offset),"localResidual":local,"referenceInstantProductionResidual":referenceResidual,"residualUnit":kind == "station" ? "degrees/day" : "degrees","bracketWidthSeconds":upper-lower,"passes60SecondReferenceGate":abs(offset)<=60]
                results.append(row)
                print("PROBE \(id)/\(eventIndex) \(kind) error=\(offset)s localResidual=\(local)")
            }
        }
        let output: [String: Any] = ["purpose":"Investigation only: local ordinary-root bisection, not certified broad coverage","ephemeris":ProcessInfo.processInfo.environment["ASTROLOGY_PROBE_MODEL"] ?? "unspecified diagnostic model","caseCount":24,"eventCount":results.count,"results":results]
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath: CommandLine.arguments[2]))
        precondition(results.count == 36)
    }
}

func probeRequire<T>(_ value: T?) throws -> T { guard let value else { throw NSError(domain:"probe",code:1) }; return value }
try ElectionAstronomyProbeTests().measureIndependentRoots()

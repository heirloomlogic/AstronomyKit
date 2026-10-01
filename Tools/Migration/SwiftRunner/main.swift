import AstronomyKit
import Foundation

enum RunnerError: Error {
    case usage
}

func model(named name: String) throws -> DeltaTModel {
    switch name {
    case "espenak-meeus": return .espenakMeeus
    case "jpl-horizons": return .jplHorizons
    default: throw RunnerError.usage
    }
}

func body(rawValue: String) throws -> CelestialBody {
    guard let value = Int32(rawValue), let body = CelestialBody(rawValue: value) else {
        throw RunnerError.usage
    }
    return body
}

func number(_ value: String) throws -> Double {
    guard let value = Double(value) else { throw RunnerError.usage }
    return value
}

func time(scale: String, value: String, model: DeltaTModel) throws -> AstroTime {
    switch scale {
    case "ut": return AstroTime(ut: try number(value), deltaTModel: model)
    case "tt": return AstroTime(tt: try number(value), deltaTModel: model)
    default: throw RunnerError.usage
    }
}

func timeValue(_ time: AstroTime) -> [String: Any] {
    ["ut": time.universalTime, "tt": time.terrestrialTime]
}

func vectorValue(_ vector: Vector3D) -> [String: Any] {
    ["x": vector.x, "y": vector.y, "z": vector.z]
}

func stateValue(_ state: StateVector) -> [String: Any] {
    [
        "x": state.position.x,
        "y": state.position.y,
        "z": state.position.z,
        "vx": state.velocity.x,
        "vy": state.velocity.y,
        "vz": state.velocity.z,
    ]
}

func statusName(_ error: Error) -> String {
    guard let error = error as? AstronomyError else { return "runner-error" }
    switch error {
    case .badTime: return "bad-time"
    case .invalidBody: return "invalid-body"
    case .invalidParameter: return "invalid-parameter"
    default: return "astronomy-error"
    }
}

func samples(count: Int, operation: () throws -> (AstroTime, [String: Any])) -> [String: Any] {
    do {
        var values: [[String: Any]] = []
        for _ in 0..<count {
            let (time, value) = try operation()
            values.append(["time": timeValue(time), "value": value])
        }
        return ["status": "success", "samples": values]
    } catch {
        return ["status": statusName(error), "samples": []]
    }
}

func run(_ arguments: [String]) throws -> [String: Any] {
    guard arguments.count >= 2 else { throw RunnerError.usage }
    let operation = arguments[0]
    let modelName = arguments[arguments.count - 1]
    let deltaT = try model(named: modelName)
    AstronomyConfig.setDeltaTModel(deltaT)
    var output: [String: Any]

    switch operation {
    case "position", "state", "distance":
        guard arguments.count == 6, let repetitions = Int(arguments[4]), repetitions > 0 else {
            throw RunnerError.usage
        }
        let body = try body(rawValue: arguments[1])
        let queryTime = try time(scale: arguments[2], value: arguments[3], model: deltaT)
        output = samples(count: repetitions) {
            if operation == "position" {
                return (queryTime, vectorValue(try body.heliocentricPosition(at: queryTime)))
            }
            if operation == "state" {
                return (queryTime, stateValue(try body.heliocentricState(at: queryTime)))
            }
            return (queryTime, ["distance": try body.distanceFromSun(at: queryTime)])
        }
    case "seasons":
        guard arguments.count == 3, let year = Int(arguments[1]) else { throw RunnerError.usage }
        do {
            let seasons = try Seasons.forYear(year)
            let events = seasons.allEvents.map { ["name": $0.name, "time": timeValue($0.time)] as [String: Any] }
            output = ["status": "success", "events": events]
        } catch {
            output = ["status": statusName(error), "events": []]
        }
    case "star":
        guard arguments.count == 6 else { throw RunnerError.usage }
        let queryTime = AstroTime(ut: try number(arguments[1]), deltaTModel: deltaT)
        let star = FixedStar(
            name: "comparison-star",
            rightAscension: try number(arguments[2]),
            declination: try number(arguments[3]),
            distance: try number(arguments[4])
        )
        output = samples(count: 1) {
            let ecliptic = try star.ecliptic(at: queryTime)
            return (
                queryTime,
                ["latitude": ecliptic.latitude, "longitude": ecliptic.longitude, "distance": ecliptic.distance]
            )
        }
    case "gravity":
        guard arguments.count == 10 else { throw RunnerError.usage }
        let start = AstroTime(ut: try number(arguments[1]), deltaTModel: deltaT)
        let target = AstroTime(ut: try number(arguments[2]), deltaTModel: deltaT)
        let initial = StateVector(
            position: Vector3D(
                x: try number(arguments[3]),
                y: try number(arguments[4]),
                z: try number(arguments[5]),
                time: start
            ),
            velocity: Vector3D(
                x: try number(arguments[6]),
                y: try number(arguments[7]),
                z: try number(arguments[8]),
                time: start
            ),
            time: start
        )
        output = samples(count: 1) {
            let simulation = try GravitySimulation(origin: .sun, time: start, initialState: initial)
            return (target, stateValue(try simulation.update(to: target)))
        }
    case "chiron":
        guard arguments.count == 3 else { throw RunnerError.usage }
        let queryTime = AstroTime(ut: try number(arguments[1]), deltaTModel: deltaT)
        output = samples(count: 1) {
            (queryTime, vectorValue(try Chiron.heliocentricPosition(at: queryTime)))
        }
    default:
        throw RunnerError.usage
    }
    output["model"] = modelName
    return output
}

do {
    let output = try run(Array(CommandLine.arguments.dropFirst()))
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0a]))
} catch {
    FileHandle.standardError.write(Data("invalid comparison request\n".utf8))
    exit(64)
}

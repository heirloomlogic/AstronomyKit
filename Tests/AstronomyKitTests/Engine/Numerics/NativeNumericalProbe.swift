import Foundation
import Testing

@testable import AstronomyKit

// The exporter is enabled only by Scripts/solar-numerics/measure.py.
@Suite(
    "Native numerical measurement export",
    .enabled(if: ProcessInfo.processInfo.environment["ASTRONOMYKIT_NUMERICS_INPUT"] != nil)
)
struct NativeNumericalProbe {
    struct Request: Codable {
        let id: String
        let days: Double
        let scale: String
        let model: String
    }

    struct Record: Codable {
        let id: String
        let scale: String
        let model: String
        let values: [String: String]
    }

    enum InvalidRequest: Error { case scale, model, days }

    static func evaluate(_ request: Request) throws -> Record {
        guard request.days.isFinite else { throw InvalidRequest.days }
        let model: DeltaTModel
        switch request.model {
        case "espenakMeeus": model = .espenakMeeus
        case "jplHorizons": model = .jplHorizons
        default: throw InvalidRequest.model
        }
        let time: Engine.Time
        switch request.scale {
        case "ut": time = Engine.Time(ut: request.days, deltaTModel: model)
        case "tt": time = Engine.Time(tt: request.days, deltaTModel: model)
        default: throw InvalidRequest.scale
        }
        let earth = try Engine.Planet.earth.heliocentricEclipticPosition(at: time)
        let nutation = Engine.Nutation.angles(tt: time.tt)
        let numbers = [
            "input": request.days, "ut": time.ut, "tt": time.tt,
            "deltaTSeconds": Engine.DeltaT.seconds(ut: time.ut, model: model),
            "forwardTT": Engine.Time(ut: time.ut, deltaTModel: model).tt,
            "eraDegrees": Engine.EarthRotation.angle(ut: time.ut),
            "nutationLongitudeDegrees": nutation.longitude,
            "nutationObliquityDegrees": nutation.obliquity,
            "earthX": earth.x, "earthY": earth.y, "earthZ": earth.z,
        ]
        guard numbers.values.allSatisfy(\.isFinite) else { throw AstronomyError.badTime }
        return Record(
            id: request.id, scale: request.scale, model: request.model,
            values: numbers.mapValues { String($0.bitPattern, radix: 16) })
    }

    @Test("Export native primitives for independent extended-precision comparison")
    func export() throws {
        let environment = ProcessInfo.processInfo.environment
        let input = try #require(environment["ASTRONOMYKIT_NUMERICS_INPUT"])
        let output = try #require(environment["ASTRONOMYKIT_NUMERICS_OUTPUT"])
        let requests = try JSONDecoder().decode([Request].self, from: Data(contentsOf: URL(fileURLWithPath: input)))
        #expect(Set(requests.map(\.id)).count == requests.count)
        let records = try requests.map(Self.evaluate)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(records).write(to: URL(fileURLWithPath: output), options: .atomic)
    }
}

@Suite("Native numerical probe input provenance")
struct NativeNumericalProbeTests {
    @Test("Each record keeps the exact supplied scale and model", arguments: ["ut", "tt"])
    func exactInput(scale: String) throws {
        let input = 36_000.0.nextDown
        let record = try NativeNumericalProbe.evaluate(
            .init(id: "test", days: input, scale: scale, model: "jplHorizons"))
        #expect(record.values[scale] == String(input.bitPattern, radix: 16))
        #expect(record.model == "jplHorizons")
        let other = try NativeNumericalProbe.evaluate(
            .init(id: "other", days: input, scale: scale, model: "espenakMeeus"))
        #expect(record.values[scale == "ut" ? "tt" : "ut"] != other.values[scale == "ut" ? "tt" : "ut"])
    }

    @Test("Malformed requests fail instead of silently selecting a model or scale")
    func malformedRequests() {
        #expect(throws: NativeNumericalProbe.InvalidRequest.model) {
            try NativeNumericalProbe.evaluate(.init(id: "bad", days: 0, scale: "ut", model: "unknown"))
        }
        #expect(throws: NativeNumericalProbe.InvalidRequest.scale) {
            try NativeNumericalProbe.evaluate(.init(id: "bad", days: 0, scale: "utc", model: "espenakMeeus"))
        }
        #expect(throws: NativeNumericalProbe.InvalidRequest.days) {
            try NativeNumericalProbe.evaluate(.init(id: "bad", days: .infinity, scale: "ut", model: "espenakMeeus"))
        }
    }
}

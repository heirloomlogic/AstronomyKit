import Foundation
import Testing

@testable import AstronomyKit

@Suite("Native safety corpus")
struct NativeSafetyTests {
    private static let corpusNames: Set<String> = [
        "audit-moon", "audit-sun", "edge-nonfinite", "edge-pluto-crawl-limit", "edge-pluto-table-start",
        "edge-polar-sun", "edge-time-range-limit", "edge-time-range-outside", "fixed-longitude-huge-target",
        "fixed-mars-distance-far-time", "fixed-moon-overflow", "fixed-neptune-huge-time", "fixed-pluto-nan",
        "fixed-riseset-infinite-limit", "fixed-riseset-stall", "fixedstar-algol", "fixedstar-undefined",
        "jpl-asheville-moon", "jpl-jupiter", "jpl-mars", "jpl-mercury", "jpl-moon", "jpl-neptune",
        "jpl-pluto", "jpl-saturn", "jpl-sun", "jpl-uranus", "jpl-venus", "riseset-london-moon",
        "riseset-nyc-sun",
    ]

    private static var corpusDirectory: URL {
        (0..<3).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
            .appendingPathComponent("Fuzzing/corpus")
    }

    @Test("Every historical input reaches native Swift entry points")
    func replayHistoricalCorpus() throws {
        let urls = try FileManager.default.contentsOfDirectory(
            at: Self.corpusDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        #expect(Set(urls.map(\.lastPathComponent)) == Self.corpusNames)
        #expect(urls.count == 30)

        var replayed = 0
        for url in urls {
            let data = try Data(contentsOf: url)
            let coverage = NativeSafetyHarness.replay(data, label: url.lastPathComponent, includeSearches: true)
            if coverage.completed {
                replayed += 1
            }
            if url.lastPathComponent == "fixed-riseset-infinite-limit" {
                #expect(coverage.fixedStarRiseSet == .rejectedInvalidParameter)
            }
        }
        #expect(replayed == urls.count)
    }

    @Test("Deterministic generated inputs preserve native invariants")
    func generatedInputs() {
        var generator = DeterministicBytes(state: 0x97_5A_FE_71)
        for index in 0..<512 {
            let count = index % 193
            let data = Data((0..<count).map { _ in generator.next() })
            _ = NativeSafetyHarness.replay(data, label: "generated-\(index)", includeSearches: false)
        }
    }

    @Test("Gravity simulation rejects a bad update without corrupting storage")
    func gravitySimulationRollback() throws {
        let time = AstroTime(year: 2025, month: 1, day: 1, deltaTModel: .espenakMeeus)
        let position = Vector3D(x: 1.2, y: -0.4, z: 0.05, time: time)
        let velocity = Vector3D(x: 0.002, y: 0.015, z: -0.001, time: time)
        let state = StateVector(position: position, velocity: velocity, time: time)
        let simulation = try GravitySimulation(origin: .sun, time: time, initialState: state)
        let before = simulation.currentTime()

        #expect(throws: AstronomyError.badTime) {
            try simulation.update(to: AstroTime(ut: .infinity, deltaTModel: .espenakMeeus))
        }
        #expect(simulation.bodyCount == 1)
        #expect(simulation.currentTime() == before)

        let advanced = try simulation.update(to: time.addingDays(0.25))
        NativeSafetyHarness.expectFinite(advanced.position, label: "gravity position")
        NativeSafetyHarness.expectFinite(advanced.velocity, label: "gravity velocity")
        #expect(simulation.bodyCount == 1)
    }
}

private struct DeterministicBytes {
    var state: UInt64

    mutating func next() -> UInt8 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return UInt8(truncatingIfNeeded: state >> 24)
    }
}

private enum NativeSafetyHarness {
    enum RiseSetReplayOutcome {
        case notRun
        case completed
        case rejectedInvalidParameter
        case rejectedOther
    }

    private enum BodySelection {
        case body(CelestialBody)
        case star(slot: Int)
        case invalid
    }

    private struct Input {
        let starRightAscension: Double
        let starDeclination: Double
        let starDistance: Double
        let time: AstroTime
        let body: BodySelection
        let observer: Observer
        let geocentricAberration: Aberration
        let equatorDate: EquatorDate
        let equatorialAberration: Aberration
        let constellationRightAscension: Double
        let constellationDeclination: Double
        let rotationValues: [Double]
        let axis: Int
        let angle: Double
        let direction: RiseSetDirection
        let limitDays: Double
        let metersAboveGround: Double

        init(_ data: Data) {
            var reader = Reader(data)
            let flags = reader.byte()
            starRightAscension = reader.double()
            starDeclination = reader.double()
            starDistance = reader.double()
            let timeValue = reader.double()
            time =
                flags & 1 == 0
                ? AstroTime(ut: timeValue, deltaTModel: flags & 2 == 0 ? .espenakMeeus : .jplHorizons)
                : AstroTime(tt: timeValue, deltaTModel: flags & 2 == 0 ? .espenakMeeus : .jplHorizons)
            body = Self.body(reader.byte())
            observer = Observer(latitude: reader.double(), longitude: reader.double(), height: reader.double())
            geocentricAberration = Self.binaryEnum(reader.byte()) ? .corrected : .none
            equatorDate = Self.binaryEnum(reader.byte()) ? .ofDate : .j2000
            equatorialAberration = Self.binaryEnum(reader.byte()) ? .corrected : .none
            constellationRightAscension = reader.double()
            constellationDeclination = reader.double()
            _ = reader.byte()
            rotationValues = (0..<9).map { _ in reader.double() }
            axis = Int(Int8(bitPattern: reader.byte()))
            angle = reader.double()
            direction = Self.binaryEnum(reader.byte()) ? .set : .rise
            limitDays = reader.double()
            metersAboveGround = reader.double()
        }

        private static func binaryEnum(_ byte: UInt8) -> Bool {
            [0, 1, 2, -2, Int.min, Int.max][Int(byte) % 6] == 1
        }

        private static func body(_ byte: UInt8) -> BodySelection {
            let values: [BodySelection] = [
                .body(.mercury), .body(.venus), .body(.earth), .body(.mars), .body(.jupiter), .body(.saturn),
                .body(.uranus), .body(.neptune), .body(.pluto), .body(.sun), .body(.moon),
                .body(.earthMoonBarycenter), .body(.solarSystemBarycenter),
                .star(slot: 1), .star(slot: 2), .star(slot: 3), .star(slot: 4), .star(slot: 5), .star(slot: 6),
                .star(slot: 7), .star(slot: 8), .invalid, .invalid, .invalid, .invalid, .invalid, .invalid, .invalid,
                .invalid, .invalid, .invalid, .invalid,
            ]
            return values[Int(byte) % values.count]
        }
    }

    static func replay(
        _ data: Data,
        label: String,
        includeSearches: Bool
    ) -> (completed: Bool, fixedStarRiseSet: RiseSetReplayOutcome) {
        let input = Input(data)
        var fixedStarRiseSet = RiseSetReplayOutcome.notRun
        let vectors = stride(from: 0, to: input.rotationValues.count, by: 3).map { offset in
            Vector3D(
                x: input.rotationValues[offset],
                y: input.rotationValues[offset + 1],
                z: input.rotationValues[offset + 2],
                time: input.time
            )
        }
        let vector = vectors[0]
        let sphere = vector.toSpherical()
        if vector.x.isFinite, vector.y.isFinite, vector.z.isFinite, vector.magnitude.isFinite {
            expectFinite(vector.normalized, label: "\(label) normalized vector")
        }
        if sphere.distance.isFinite {
            #expect(sphere.distance >= 0, "\(label) produced a negative spherical distance")
        }

        observe(label, "rotation pivot") {
            let rotation = try RotationMatrix.pivot(axis: input.axis, angle: input.angle)
            for (index, candidate) in vectors.enumerated() {
                let rotated = try candidate.rotated(by: rotation)
                if input.angle.isFinite,
                    [candidate.x, candidate.y, candidate.z].allSatisfy({ $0.isFinite && abs($0) < 1e150 })
                {
                    expectFinite(rotated, label: "\(label) rotated vector row \(index)")
                }
            }
        }
        observe(label, "constellation") {
            let result = try Constellation.find(
                rightAscension: input.constellationRightAscension,
                declination: input.constellationDeclination
            )
            #expect(!result.symbol.isEmpty, "\(label) returned an empty constellation symbol")
        }

        switch input.body {
        case .body(let body):
            exercise(body, input: input, label: label, includeSearches: includeSearches)
        case .star(let slot):
            fixedStarRiseSet = exerciseStar(slot: slot, input: input, label: label, includeSearches: includeSearches)
        case .invalid:
            _ = input.time.siderealTime(longitude: input.observer.longitude)
        }

        let libration = Moon.libration(at: input.time)
        if input.time.terrestrialTime.isFinite, abs(input.time.terrestrialTime) <= 1_461_000 {
            #expect(libration.distanceKM.isFinite, "\(label) produced nonfinite native libration")
        }
        if includeSearches {
            observe(label, "lunar node") {
                let node = try Moon.searchNode(after: input.time)
                #expect(node.time.terrestrialTime.isFinite, "\(label) produced a nonfinite lunar node")
            }
        }
        return (completed: true, fixedStarRiseSet: fixedStarRiseSet)
    }

    private static func exercise(_ body: CelestialBody, input: Input, label: String, includeSearches: Bool) {
        observe(label, "heliocentric position") {
            let result = try body.heliocentricPosition(at: input.time)
            expectFinite(result, label: "\(label) heliocentric position")
        }
        observe(label, "heliocentric distance") {
            let result = try body.distanceFromSun(at: input.time)
            #expect(result.isFinite && result >= 0, "\(label) produced invalid heliocentric distance \(result)")
        }
        observe(label, "geocentric position") {
            let result = try body.geocentricPosition(at: input.time, aberration: input.geocentricAberration)
            expectFinite(result, label: "\(label) geocentric position")
        }
        observe(label, "equatorial position") {
            let result = try body.equatorial(
                at: input.time,
                from: input.observer,
                equatorDate: input.equatorDate,
                aberration: input.equatorialAberration
            )
            #expect(
                result.rightAscension.isFinite && result.declination.isFinite && result.distance.isFinite,
                "\(label) produced invalid equatorial coordinates")
        }

        guard includeSearches else { return }
        if input.limitDays.isFinite, abs(input.limitDays) <= 366 {
            observe(label, "rise/set search") {
                _ = try body.searchRiseSet(
                    direction: input.direction,
                    after: input.time,
                    from: input.observer,
                    limitDays: input.limitDays,
                    metersAboveGround: input.metersAboveGround
                )
            }
        }
        if body == .sun {
            observe(label, "solar longitude search") {
                _ = try Sun.searchLongitude(input.angle, after: input.time, limitDays: input.limitDays)
            }
        } else if [.mercury, .venus, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto].contains(body) {
            observe(label, "relative longitude search") {
                let result = try body.searchRelativeLongitude(input.angle, after: input.time)
                #expect(result.terrestrialTime.isFinite, "\(label) produced a nonfinite longitude event")
            }
            observe(label, "apsis search") {
                let result = try body.searchApsis(after: input.time)
                #expect(
                    result.time.terrestrialTime.isFinite && result.distanceAU.isFinite,
                    "\(label) produced an invalid apsis")
            }
        }
    }

    private static func exerciseStar(
        slot: Int,
        input: Input,
        label: String,
        includeSearches: Bool
    ) -> RiseSetReplayOutcome {
        let nativeStar = Engine.Star(
            rightAscension: input.starRightAscension,
            declination: input.starDeclination,
            distance: input.starDistance
        )
        let star = FixedStar(
            name: "fuzz-star-\(slot)",
            rightAscension: input.starRightAscension,
            declination: input.starDeclination,
            distance: input.starDistance
        )
        observe(label, "fixed-star equatorial position") {
            let result = try star.equatorial(at: input.time, from: input.observer, equatorDate: input.equatorDate)
            #expect(
                result.rightAscension.isFinite && result.declination.isFinite && result.distance.isFinite,
                "\(label) produced invalid fixed-star coordinates")
        }
        guard includeSearches else { return .notRun }
        do {
            _ = try Engine.Events.searchRiseSet(
                of: .star(nativeStar),
                direction: input.direction,
                after: input.time.engine,
                from: input.observer,
                limitDays: input.limitDays,
                heightAboveGround: input.metersAboveGround
            )
            return .completed
        } catch AstronomyError.invalidParameter {
            return .rejectedInvalidParameter
        } catch AstronomyError.unknown(let status) {
            Issue.record("\(label) fixed-star rise/set returned unknown status \(status)")
        } catch is AstronomyError {
            return .rejectedOther
        } catch {
            Issue.record("\(label) fixed-star rise/set threw unexpected error: \(error)")
        }
        return .rejectedOther
    }

    static func expectFinite(_ vector: Vector3D, label: String) {
        #expect(vector.x.isFinite && vector.y.isFinite && vector.z.isFinite, "\(label) is nonfinite")
    }

    private static func observe(_ input: String, _ operation: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch AstronomyError.unknown(let status) {
            Issue.record("\(input) \(operation) returned unknown status \(status)")
        } catch is AstronomyError {
            // A typed failure is a valid native response to malformed input.
        } catch {
            Issue.record("\(input) \(operation) threw unexpected error: \(error)")
        }
    }

    private struct Reader {
        private var bytes: [UInt8]
        private var index = 0

        init(_ data: Data) {
            bytes = Array(data)
        }

        mutating func byte() -> UInt8 {
            defer { index += 1 }
            return index < bytes.count ? bytes[index] : 0
        }

        mutating func littleEndian(_ count: Int) -> UInt64 {
            var value: UInt64 = 0
            for offset in 0..<count {
                value |= UInt64(byte()) << UInt64(8 * offset)
            }
            return value
        }

        mutating func double() -> Double {
            let tag = byte()
            switch tag & 3 {
            case 0:
                return Double(bitPattern: littleEndian(8))
            case 1:
                return Self.specialValues[Int(tag >> 2) % Self.specialValues.count]
            case 2:
                return Double(Int16(bitPattern: UInt16(truncatingIfNeeded: littleEndian(2)))) / 256
            default:
                return Double(Int32(bitPattern: UInt32(truncatingIfNeeded: littleEndian(4))))
            }
        }

        private static let specialValues: [Double] = [
            0, -0.0, 1, -1, 0.5, 90, -90, 89.99999999999999, -89.99999999999999, 90.00000000000001,
            180, -180, 360, -360, 24, 23.999999999999996, .nan, -.nan, .infinity, -.infinity,
            .greatestFiniteMagnitude, -.greatestFiniteMagnitude, .leastNormalMagnitude, -.leastNormalMagnitude,
            .leastNonzeroMagnitude, .ulpOfOne, 1e300, -1e300, 1e-300, 9_007_199_254_740_992,
            -9_007_199_254_740_992, 1e16, -1e16, 1e9, -1e9, 2_147_483_647, -2_147_483_648,
            4_294_967_296, -730_000, 730_000, -766_525, 766_525, -766_525.5, 766_525.5,
            36_525, -36_525, 1_461_000, -1_461_000, 366, -366, 0.42, -0.42, 100_000, -500,
            100_000.5, -500.5, .pi, 2 * .pi, 1e-9, -1e-9, 1e-15, 63_241.07708426628,
            0.9999999999999999, 1.0000000000000002,
        ]
    }
}

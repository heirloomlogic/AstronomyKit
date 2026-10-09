import Testing

@testable import AstronomyKit

@Suite("Native position facades")
struct NativePositionFacadeTests {
    @Test("Public reset clears native caches and preserves values and owned simulations")
    func reset() throws {
        let cache = Engine.BoundedCache<Int, Int>(capacity: 2, registry: .shared)
        _ = cache.value(for: 1) { 42 }
        let time = AstroTime(ut: 9_496, deltaTModel: .jplHorizons)
        let star = FixedStar(name: "Reset", rightAscension: 3.1, declination: 40.9, distance: 93)
        let expected = try star.equatorial(at: time)
        let state = try CelestialBody.mars.heliocentricState(at: time)
        let simulation = try GravitySimulation(origin: .sun, time: time, initialState: state)
        let earth = try simulation.state(of: .earth)
        AstronomyConfig.reset()
        #expect(cache.count == 0)
        #expect(time.deltaTModel == .jplHorizons)
        #expect(try star.equatorial(at: time) == expected)
        #expect(try simulation.state(of: .earth) == earth)
        #expect(try CelestialBody.mars.heliocentricState(at: time) == state)
    }

    @Test(
        "Body states expose native geometric positions without deriving time",
        arguments: [DeltaTModel.espenakMeeus, .jplHorizons])
    func bodies(model: DeltaTModel) throws {
        let time = AstroTime(tt: 9_496.375, ut: 123, deltaTModel: model)
        let native = Engine.Time(ut: time.universalTime, tt: time.terrestrialTime, deltaTModel: model)
        for body in [
            CelestialBody.sun, .moon, .mercury, .venus, .earth, .mars, .jupiter, .saturn, .uranus, .neptune, .pluto,
            .earthMoonBarycenter, .solarSystemBarycenter,
        ] {
            let vector = try body.heliocentricPosition(at: time)
            let expected = try Engine.Positions.heliocentricPosition(of: body, at: native)
            #expect(vector.x == expected.x && vector.y == expected.y && vector.z == expected.z)
            for state in [try body.heliocentricState(at: time), try body.barycentricState(at: time)] {
                #expect(state.time.universalTime == time.universalTime)
                #expect(state.time.terrestrialTime == time.terrestrialTime)
                #expect(state.time.deltaTModel == model)
                #expect(state.position.time.terrestrialTime == time.terrestrialTime)
                #expect(state.velocity.time.terrestrialTime == time.terrestrialTime)
            }
            #expect(vector.time.universalTime == time.universalTime)
            #expect(vector.time.terrestrialTime == time.terrestrialTime)
            #expect(vector.time.deltaTModel == model)
        }
    }

    @Test("Fixed-star output uses immutable native catalog values")
    func star() throws {
        let time = AstroTime(ut: 9_496.375, deltaTModel: .jplHorizons)
        let nativeTime = Engine.Time(ut: time.universalTime, tt: time.terrestrialTime, deltaTModel: .jplHorizons)
        let star = FixedStar(name: "Sirius", rightAscension: 6.7525, declination: -16.7161, distance: 8.6)
        let native = Engine.Star(
            rightAscension: star.rightAscension, declination: star.declination, distance: star.distance)
        for equator in [EquatorDate.j2000, .ofDate] {
            let actual = try star.equatorial(at: time, from: .greenwich, equatorDate: equator)
            let expected = try native.equatorial(at: nativeTime, from: .greenwich, equatorDate: equator)
            #expect(actual.rightAscension == expected.rightAscension)
            #expect(actual.declination == expected.declination)
            #expect(actual.distance == expected.distance)
            #expect(actual.time.terrestrialTime == time.terrestrialTime)
            #expect(actual.time.deltaTModel == .jplHorizons)
        }
    }

    @Test("Gravity swaps preserve requested and current epochs separately")
    func simulationEpochs() throws {
        let first = AstroTime(tt: 9_496.375, ut: 123, deltaTModel: .jplHorizons)
        let second = AstroTime(tt: first.terrestrialTime + 1, ut: 456, deltaTModel: .espenakMeeus)
        let initial = StateVector(
            position: Vector3D(x: 2, y: 0, z: 0, time: second), velocity: Vector3D(x: 0, y: 0.01, z: 0, time: second),
            time: second)
        let simulation = try GravitySimulation(origin: .sun, time: first, initialState: initial)
        let result = try simulation.update(to: second)
        #expect(result.time.terrestrialTime == second.terrestrialTime)
        simulation.swap()
        #expect(simulation.time.universalTime == second.universalTime)
        #expect(simulation.currentTime().universalTime == first.universalTime)
        #expect(simulation.currentTime().deltaTModel == first.deltaTModel)
        #expect(try simulation.state(of: .earth).time.terrestrialTime == first.terrestrialTime)
        let sameTT = AstroTime(tt: first.terrestrialTime, ut: -789, deltaTModel: .espenakMeeus)
        let same = try simulation.update(to: sameTT)
        #expect(same.time.universalTime == sameTT.universalTime)
        #expect(simulation.time.universalTime == sameTT.universalTime)
        #expect(simulation.currentTime().universalTime == first.universalTime)
        #expect(throws: AstronomyError.badTime) { try simulation.update(to: AstroTime(ut: .nan)) }
        #expect(simulation.currentTime().universalTime == first.universalTime)
        #expect(simulation.bodyCount == 1)
    }
}

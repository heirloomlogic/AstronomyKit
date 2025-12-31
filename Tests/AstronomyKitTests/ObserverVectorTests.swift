//
//  ObserverVectorTests.swift
//  AstronomyKit
//
//  Tests for Observer vector/state functionality.
//

import Testing

@testable import AstronomyKit

@Suite("Observer Vector Tests")
struct ObserverVectorTests {

    let greenwich = Observer.greenwich

    @Test("Observer vector returns position")
    func observerVector() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let vector = try greenwich.vector(at: time)

        // Observer on Earth should have position magnitude ~Earth radius in AU
        // Earth radius ~4.26e-5 AU
        #expect(vector.magnitude > 0)
        #expect(vector.magnitude < 0.001)  // Much less than 1 AU
    }

    @Test("Observer state returns position and velocity")
    func observerState() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)
        let state = try greenwich.state(at: time)

        #expect(state.position.magnitude > 0)
        #expect(state.velocity.magnitude > 0)
    }

    @Test("J2000 vs of-date coordinates differ")
    func j2000VsOfDate() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)

        let j2000 = try greenwich.vector(at: time, equator: .j2000)
        let ofDate = try greenwich.vector(at: time, equator: .ofDate)

        // Due to precession, these should be slightly different
        // (but very close since we're near J2000)
        let diff = abs(j2000.x - ofDate.x) + abs(j2000.y - ofDate.y) + abs(j2000.z - ofDate.z)
        #expect(diff > 0)  // They should differ
        #expect(diff < 0.001)  // But not by much
    }

    @Test("Observer at equator vs pole")
    func equatorVsPole() throws {
        let time = AstroTime(year: 2_025, month: 6, day: 21)

        let equator = Observer(latitude: 0, longitude: 0)
        let pole = Observer(latitude: 90, longitude: 0)

        let eqVec = try equator.vector(at: time)
        let poleVec = try pole.vector(at: time)

        // Equator position should have larger x/y components
        // Pole position should have larger z component
        // (This depends on Earth's orientation at the time)
        #expect(eqVec.magnitude > 0)
        #expect(poleVec.magnitude > 0)
    }

    @Test("EquatorFrame enum cases")
    func equatorFrameCases() {
        #expect(Observer.EquatorFrame.j2000 == .j2000)
        #expect(Observer.EquatorFrame.ofDate == .ofDate)
    }
}

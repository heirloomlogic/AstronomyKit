import XCTest
@testable import AstronomyKit

final class AstronomyKitTests: XCTestCase {
    
    // MARK: - Time Tests
    
    func testAstroTimeFromComponents() {
        let time = AstroTime(year: 2000, month: 1, day: 1, hour: 12)
        XCTAssertEqual(time.ut, 0, accuracy: 0.0001, "J2000 epoch should be ut=0")
    }
    
    func testAstroTimeFromDate() {
        let date = Date(timeIntervalSince1970: 946728000) // 2000-01-01T12:00:00Z
        let time = AstroTime(date)
        XCTAssertEqual(time.ut, 0, accuracy: 0.001, "J2000 epoch from Date should be ut≈0")
    }
    
    func testAstroTimeAddDays() {
        let time = AstroTime(year: 2000, month: 1, day: 1)
        let later = time.addingDays(1)
        XCTAssertEqual(later.ut - time.ut, 1, accuracy: 0.0001)
    }
    
    func testAstroTimeComparable() {
        let earlier = AstroTime(year: 2000, month: 1, day: 1)
        let later = AstroTime(year: 2000, month: 1, day: 2)
        XCTAssertLessThan(earlier, later)
    }
    
    // MARK: - Observer Tests
    
    func testObserverCreation() {
        let observer = Observer(latitude: 40.7128, longitude: -74.0060, height: 10)
        XCTAssertEqual(observer.latitude, 40.7128)
        XCTAssertEqual(observer.longitude, -74.0060)
        XCTAssertEqual(observer.height, 10)
    }
    
    func testObserverGravity() {
        let equator = Observer(latitude: 0, longitude: 0)
        let pole = Observer(latitude: 90, longitude: 0)
        // Gravity is slightly higher at the poles
        XCTAssertGreaterThan(pole.gravity, equator.gravity)
    }
    
    // MARK: - Celestial Body Tests
    
    func testCelestialBodyName() {
        XCTAssertEqual(CelestialBody.sun.name, "Sun")
        XCTAssertEqual(CelestialBody.moon.name, "Moon")
        XCTAssertEqual(CelestialBody.mars.name, "Mars")
    }
    
    func testCelestialBodyFromName() {
        XCTAssertEqual(CelestialBody(name: "Mars"), .mars)
        // Note: Case sensitivity depends on C library implementation
        // Just verify invalid names return nil
        XCTAssertNil(CelestialBody(name: "InvalidBody"))
    }
    
    func testCelestialBodyCategories() {
        XCTAssertTrue(CelestialBody.mars.isPlanet)
        XCTAssertFalse(CelestialBody.moon.isPlanet)
        XCTAssertTrue(CelestialBody.saturn.isNakedEyeVisible)
        XCTAssertFalse(CelestialBody.neptune.isNakedEyeVisible)
    }
    
    // MARK: - Position Tests
    
    func testGeoPosition() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let position = try CelestialBody.mars.geoPosition(at: time)
        XCTAssertGreaterThan(position.magnitude, 0)
    }
    
    func testHelioPosition() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let position = try CelestialBody.earth.helioPosition(at: time)
        // Earth is about 1 AU from the Sun
        XCTAssertEqual(position.magnitude, 1.0, accuracy: 0.02)
    }
    
    func testHorizonPosition() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21, hour: 12)
        let observer = Observer(latitude: 40.7128, longitude: -74.0060)
        let horizon = try CelestialBody.sun.horizon(at: time, from: observer)
        // Sun should be above horizon at noon in NYC in June
        XCTAssertTrue(horizon.isAboveHorizon)
    }
    
    // MARK: - Moon Phase Tests
    
    func testMoonPhaseAngle() throws {
        let time = AstroTime.now
        let angle = try Moon.phaseAngle(at: time)
        XCTAssertGreaterThanOrEqual(angle, 0)
        XCTAssertLessThan(angle, 360)
    }
    
    func testMoonPhaseName() {
        XCTAssertEqual(Moon.phaseName(for: 0), "New Moon")
        XCTAssertEqual(Moon.phaseName(for: 90), "First Quarter")
        XCTAssertEqual(Moon.phaseName(for: 180), "Full Moon")
        XCTAssertEqual(Moon.phaseName(for: 270), "Third Quarter")
    }
    
    func testMoonIllumination() {
        XCTAssertEqual(Moon.illumination(for: 0), 0, accuracy: 0.01)
        XCTAssertEqual(Moon.illumination(for: 90), 0.5, accuracy: 0.01)
        XCTAssertEqual(Moon.illumination(for: 180), 1.0, accuracy: 0.01)
    }
    
    func testMoonQuarterSearch() throws {
        let time = AstroTime(year: 2025, month: 1, day: 1)
        let quarter = try Moon.searchQuarter(after: time)
        XCTAssertGreaterThan(quarter.time, time)
    }
    
    // MARK: - Seasons Tests
    
    func testSeasons() throws {
        let seasons = try Seasons.forYear(2025)
        
        // Verify the order is correct
        XCTAssertLessThan(seasons.marchEquinox, seasons.juneSolstice)
        XCTAssertLessThan(seasons.juneSolstice, seasons.septemberEquinox)
        XCTAssertLessThan(seasons.septemberEquinox, seasons.decemberSolstice)
        
        // Check approximate dates
        let marchDate = seasons.marchEquinox.date
        let calendar = Calendar(identifier: .gregorian)
        let month = calendar.component(.month, from: marchDate)
        XCTAssertEqual(month, 3)
    }
    
    // MARK: - Rise/Set Tests
    
    func testSunrise() throws {
        let time = AstroTime(year: 2025, month: 6, day: 21)
        let observer = Observer(latitude: 40.7128, longitude: -74.0060)
        
        let sunrise = try CelestialBody.sun.riseTime(after: time, from: observer)
        XCTAssertNotNil(sunrise)
        
        if let sunrise = sunrise {
            XCTAssertGreaterThan(sunrise, time)
        }
    }
    
    // MARK: - Eclipse Tests
    
    func testLunarEclipseSearch() throws {
        let time = AstroTime(year: 2025, month: 1, day: 1)
        let eclipse = try Eclipse.searchLunar(after: time)
        XCTAssertGreaterThan(eclipse.peak, time)
        XCTAssertNotEqual(eclipse.kind, .none)
    }
    
    func testSolarEclipseSearch() throws {
        let time = AstroTime(year: 2025, month: 1, day: 1)
        let eclipse = try Eclipse.searchGlobalSolar(after: time)
        XCTAssertGreaterThan(eclipse.peak, time)
        XCTAssertNotEqual(eclipse.kind, .none)
    }
}

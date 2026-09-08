//
//  ScanThroughputBenchmarkTests.swift
//  AstrologyKitTests
//
//  Coarse performance guardrails for the scoring/scan hot path. These are NOT
//  precise microbenchmarks — the ceilings carry ~10x headroom so they stay green
//  on slow/shared CI runners while still catching a return of O(n^2)-class
//  regressions (e.g. the per-instance `flagInstances` scans that FlagInstanceIndex
//  replaced). Measured durations are printed so trend data lives in CI logs.
//

import Foundation

@testable import AstrologyKit

struct ScanThroughputBenchmarkTests {
    /// A deterministic spread of observers across latitudes/hemispheres.
    private static let observers: [(name: String, lat: Double, lon: Double)] = [
        ("Reykjavik", 64.15, -21.95),
        ("Anchorage", 61.22, -149.90),
        ("London", 51.51, -0.13),
        ("New York", 40.71, -74.01),
        ("Tokyo", 35.68, 139.69),
        ("Singapore", 1.35, 103.82),
        ("Brisbane", -27.47, 153.03),
        ("Auckland", -36.85, 174.76),
    ]

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = hour
        c.minute = 0
        c.timeZone = TimeZone(identifier: "UTC")
        guard let date = Calendar(identifier: .gregorian).date(from: c) else {
            fatalError("Invalid date components: \(year)-\(month)-\(day)T\(hour):00")
        }
        return date
    }

    /// Scoring throughput: build a spread of charts, then score each under several
    /// intents. Guards the per-chart scoring pass (the FlagInstanceIndex target).
    ///
    /// Each chart carries its own populated ``EphemerisCache`` rather than `.empty`, so the
    /// measured loop is the path production takes (#255). One cache cannot serve the spread:
    /// ``RiseSetTable`` answers for the observer it searched from and the syzygy table for
    /// the range it walked, and this suite deliberately spans eight observers and eight
    /// epochs. A degenerate single-timestamp range per chart is the same cache the
    /// calibration corpus builds for one moment (#178), and building them sits outside the
    /// measurement.

    func scoringThroughput() async throws {
        // Build ~120 charts once (chart construction is not what we're measuring).
        let setupClock = ContinuousClock()
        let setupStart = setupClock.now
        var charts: [(state: ChartState, ephemeris: EphemerisCache)] = []
        let years = [1955, 1972, 1988, 1999, 2011, 2024, 2037, 2050]
        for (i, year) in years.enumerated() {
            for obs in Self.observers {
                let d = Self.date(year, ((year + i) % 12) + 1, ((year + i) % 27) + 1, (year + i) % 24)
                charts.append(
                    (
                        try await ScanService.shared.chartState(
                            at: d, latitude: obs.lat, longitude: obs.lon
                        ),
                        EphemerisCache.forScan(
                            from: d,
                            to: d,
                            observer: Observer(latitude: obs.lat, longitude: obs.lon)
                        )
                    )
                )
            }
        }

        let intents = [
            Intent(domain: .business, mode: .launch),
            Intent(domain: .romance, mode: .petition),
            Intent(domain: .health, mode: .confront),
            Intent(domain: .wealth, mode: .speculate),
            Intent(domain: .contracts, mode: .sign),
        ]

        print("BENCHMARK setup: \(setupStart.duration(to: setupClock.now))")
        print("BENCHMARK scoring setup complete: \(charts.count) charts; starting timed loop")
        let clock = ContinuousClock()
        var sink = 0
        let elapsed = clock.measure {
            for chart in charts {
                for intent in intents {
                    sink &+=
                        ScoringEngine.score(
                            for: chart.state, intent: intent, ephemeris: chart.ephemeris
                        ).score
                }
            }
        }

        let scorings = charts.count * intents.count
        print(
            "BENCHMARK scoring: \(scorings) scorings in \(elapsed) "
                + "(\(elapsed / scorings) each) [checksum \(sink)]"
        )
        // Generous ceiling: 64 charts x 5 intents = 320 scorings, ~0.6s locally.
        // Even a heavily loaded CI runner clears 30s; O(n^2) regressions would not.
        if elapsed >= .seconds(30) { print("SCORING_CAP_FAILED") }
    }

}
@main enum Probe { static func main() async throws {
        try await ScanThroughputBenchmarkTests().scoringThroughput()
        if let path = ProcessInfo.processInfo.environment["CHRONOLOGY_TRACE_PATH"] { try ChronologyExperiment.writeTrace(path) }
    } }

// Civil UTC and Terrestrial Time conversion. Native UT remains modeled UT1.
// Before the USNO table starts in 1961, civil dates use the historical UT1 proxy.

enum CivilTime {
    struct Segment: Sendable {
        let start: Double  // UTC calendar days since J2000 noon
        let offset: Double  // TT-UTC seconds at start
        let rate: Double  // additional offset seconds per UTC day

        var terrestrialStart: Double { start + offset / 86_400 }
    }

    static func terrestrialTime(utcDays: Double) -> Double? {
        guard utcDays.isFinite,
            let segment = segments.last(where: { utcDays >= $0.start })
        else { return nil }
        return utcDays + (segment.offset + segment.rate * (utcDays - segment.start)) / 86_400
    }

    static func utcDays(terrestrialTime tt: Double, universalTime ut: Double) -> Double {
        guard tt.isFinite else { return .nan }
        var nextStart = Double.infinity
        // Later occurrences win where a negative historical UTC step overlaps.
        for segment in segments.reversed() {
            if tt >= segment.terrestrialStart {
                let utc = segment.start + (tt - segment.terrestrialStart) / (1 + segment.rate / 86_400)
                // Foundation Date cannot represent positive leap seconds. Map
                // those gaps to the following civil transition, without iteration.
                return min(utc, nextStart)
            }
            nextStart = segment.start
        }
        // Include the transition gap between the historical proxy and the table.
        return min(ut, segments[0].start)
    }
}

//
//  AstronomyKit.swift
//  AstronomyKit
//
//  AstronomyKit wraps the [Astronomy Engine](https://github.com/cosinekitty/astronomy) library by
//  Don Cross, exposing the underlying C functionality through idiomatic Swift APIs for calculating:
//
//  - Positions for the Sun, Moon, planets, and Jupiter's moons
//  - Moon phase angles, quarters, illumination, and libration
//  - User-defined fixed stars from J2000 catalog coordinates
//  - Gravity-simulated position for 2060 Chiron
//  - Rise, set, and culmination times
//  - Lunar and solar eclipse predictions
//  - Equinoxes and solstices
//  - Coordinate transforms across equatorial, ecliptic, horizon, and galactic systems
//  - Apsides, elongation, and transits
//  - Lagrange points and lunar nodes
//  - Full `Sendable` conformance for Swift 6
//
//  ## Quick Start
//
//  ```swift
//  import AstronomyKit
//
//  // Get current moon phase
//  let angle = try Moon.phaseAngle(at: .now)
//  print(Moon.phaseName(for: angle))
//
//  // Find next sunrise
//  let seattle = Observer(latitude: 47.6062, longitude: -122.3321)
//  if let sunrise = try CelestialBody.sun.riseTime(after: .now, from: seattle) {
//      print("Sunrise: \(sunrise)")
//  }
//
//  // Get Mars position
//  let mars = try CelestialBody.mars.horizon(at: .now, from: seattle)
//  print(mars)
//  ```
//

import CLibAstronomy

// MARK: - Delta T Models

/// The Delta T model used to convert between Universal Time and Terrestrial Time.
///
/// Delta T is TT − UT1. A civil `AstroTime(Date)` takes TT exactly from the
/// leap-second table and recovers UT1 by inverting the selected model, so the
/// model sets Earth's rotation angle, hour angles, azimuths and rise and set
/// times for every civil instant.
public enum DeltaTModel: Sendable, CaseIterable {
    /// The default: observed Earth rotation.
    ///
    /// - From 1962-01-01 through the table's last observation: daily UT1 − UTC
    ///   from IERS EOP 20 C04, then IERS Bulletin A rapid values, with
    ///   Delta T = (TAI − UTC) + 32.184 s − (UT1 − UTC), linear in UT1 between
    ///   the 0h UTC rows. Linear interpolation departs from the 12h C04 samples
    ///   by at most 0.16 ms (rms 0.019 ms, 1984–2026).
    /// - About a year after that: IERS Bulletin A predictions.
    /// - From −720 to 1962: the Table S15 v2020 spline of Morrison, Stephenson,
    ///   Hohenkerk and Zawilski (2021), the 2020 addendum to Stephenson,
    ///   Morrison and Hohenkerk (2016), as published by HM Nautical Almanac
    ///   Office. Its last segment, 1959–1962, is corrected linearly by 0.376 s
    ///   so that it meets the first C04 value.
    /// - Before −720 and after the last prediction: the integral of HMNAO's
    ///   long-term length-of-day model, lod = 1.72 t − 3.5 sin(2π(t + 0.75)/14)
    ///   ms with t in centuries from 1825.0, continuous with the value at the
    ///   join.
    ///
    /// ``AstronomyConfig/deltaTIersObservedRegime(universalTime:)`` reports
    /// which source applies at a time, and
    /// ``AstronomyConfig/deltaTIersObservedUncertainty(universalTime:)`` the
    /// stated uncertainty. ``AstronomyConfig/ephemerisVersion`` names the table.
    case iersObserved

    /// The Espenak-Meeus polynomials, Astronomy Engine's upstream default.
    ///
    /// From 2005 they extrapolate a Delta T that reaches 75.6 s by late 2026,
    /// while observed Delta T has held near 69.2 s since 2019, so present-day
    /// UT1 runs about 6.3 s late. Use it to compare with tools built on the
    /// same model.
    case espenakMeeus

    /// Espenak-Meeus through 2017.0, then held at its 2017.0 value of about
    /// 70.0 s: the approximation JPL Horizons used for the future. Use it to
    /// compare with Horizons output generated under that convention.
    case jplHorizons
}

/// The source of the default Delta T model at a given time.
///
/// See ``DeltaTModel/iersObserved``.
public enum DeltaTRegime: Sendable, CaseIterable {
    /// Before −720: HMNAO's long-term length-of-day model, continuous with
    /// the spline at −720.
    case extrapolatedPast

    /// From −720 to the first IERS row on 1962-01-01: the Table S15 v2020
    /// spline.
    case historical

    /// IERS EOP 20 C04, then IERS Bulletin A rapid determinations.
    case observed

    /// IERS Bulletin A predictions, about a year beyond the observations.
    case predicted

    /// After the last prediction: HMNAO's long-term length-of-day model,
    /// continuous with the last prediction.
    case extrapolatedFuture
}

// MARK: - Module-Level Functions

/// Module-level configuration and utility functions.
public enum AstronomyConfig {
    /// Numerical model identifier for provenance and version-dependent caches.
    /// Changes to this value require reviewing cached positions and event times.
    /// Persisted numerical caches must also account for platform, architecture,
    /// OS, and toolchain: native math does not guarantee identical output bits.
    ///
    /// The `deltat-` component names the default Delta T table: IERS EOP 20
    /// C04 through the given date, Bulletin A predictions through the given
    /// date, and the 2020 historical spline.
    public static let ephemerisVersion =
        "3.2.0+vsop87b-comp.poly-v2.iau2000b.utc-c72.deltat-iers-c04-20260917-pred-20271004-smh2020.native-libm"

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the default observed model, ``DeltaTModel/iersObserved``.
    ///
    /// - Parameter universalTime: UT1 days since J2000 noon.
    /// - Returns: Delta T in seconds. NaN for NaN input.
    public static func deltaTIersObserved(universalTime: Double) -> Double {
        Astronomy_DeltaT_IersObserved(universalTime)
    }

    /// The stated uncertainty of ``deltaTIersObserved(universalTime:)``.
    ///
    /// This is a stated, sourced uncertainty of about one standard error, not
    /// a proved bound, chosen by regime:
    ///
    /// - Observed: the row's published UT1 − UTC error (the C04 formal error,
    ///   then Bulletin A's), linear between rows, plus up to 0.16 ms at midday
    ///   for linear interpolation, the largest departure measured against the
    ///   12h C04 samples. About 0.02 ms today, 2 ms in 1962.
    /// - Predicted: Bulletin A's stated error for each prediction, from
    ///   0.6 ms on the first day to 24 ms a year ahead.
    /// - Historical: HMNAO's error estimate ε (180 s at −720, 15 s from 1000
    ///   to 1600, 0.05 s after 1870), but never less than 0.68 s, the spline's
    ///   largest departure from C04 over 1962–2019. HMNAO does not state a
    ///   confidence level for ε.
    /// - Extrapolated: HMNAO's error estimate for its extrapolation (2 s at
    ///   2030, 10 s at 2100, 100 s at 2500, 360 s at −800, 0.3 h at −2000),
    ///   linear between its years and never less than the last prediction's
    ///   error. Beyond −2000 and 2500 no figure is published; the estimate
    ///   grows with the square of the time from 1825.0, as the long-term
    ///   model's tidal term does.
    ///
    /// The value is the same whichever model is selected.
    ///
    /// - Parameter universalTime: UT1 days since J2000 noon.
    /// - Returns: The uncertainty in seconds. NaN for NaN input.
    public static func deltaTIersObservedUncertainty(universalTime: Double) -> Double {
        Astronomy_DeltaTUncertainty_IersObserved(universalTime)
    }

    /// The source ``deltaTIersObserved(universalTime:)`` draws on at a time.
    ///
    /// - Parameter universalTime: UT1 days since J2000 noon.
    /// - Returns: The regime, or `nil` for NaN input.
    public static func deltaTIersObservedRegime(universalTime: Double) -> DeltaTRegime? {
        switch Astronomy_DeltaTRegime_IersObserved(universalTime) {
        case DELTAT_REGIME_EXTRAPOLATED_PAST: .extrapolatedPast
        case DELTAT_REGIME_HISTORICAL: .historical
        case DELTAT_REGIME_OBSERVED: .observed
        case DELTAT_REGIME_PREDICTED: .predicted
        case DELTAT_REGIME_EXTRAPOLATED_FUTURE: .extrapolatedFuture
        default: nil
        }
    }

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the Espenak-Meeus model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTEspenakMeeus(universalTime: Double) -> Double {
        Astronomy_DeltaT_EspenakMeeus(universalTime)
    }

    /// Calculates the Delta T value (TT - UT) for a given Universal Time
    /// using the JPL Horizons model.
    ///
    /// - Parameter universalTime: Universal Time days since J2000 noon.
    /// - Returns: Delta T in seconds.
    public static func deltaTJplHorizons(universalTime: Double) -> Double {
        Astronomy_DeltaT_JplHorizons(universalTime)
    }

    /// Sets the Delta T model used for all subsequent calculations.
    ///
    /// The default is ``DeltaTModel/iersObserved``; no call is needed to use
    /// it. Delta T is the difference between Terrestrial Time and Universal
    /// Time.
    ///
    /// - Note: This is safe to call from any thread at any time. A
    ///   calculation already in flight on another thread may use either the
    ///   old or the new model for that one calculation, so for reproducible
    ///   results set the model once at startup.
    ///
    /// - Parameter model: The Delta T model to use.
    public static func setDeltaTModel(_ model: DeltaTModel) {
        switch model {
        case .iersObserved:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_IersObserved)
        case .espenakMeeus:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_EspenakMeeus)
        case .jplHorizons:
            Astronomy_SetDeltaTFunction(Astronomy_DeltaT_JplHorizons)
        }
    }

    /// Frees all dynamic memory allocated by the Astronomy Engine.
    ///
    /// The engine allocates memory in only one place: a cache of orbit
    /// segments that speeds up Pluto calculations. This purges that cache,
    /// which slows down the next nearby Pluto calculation but releases the
    /// memory (useful before running leak checkers). It does not affect the
    /// Delta T model or any ``FixedStar`` definitions.
    ///
    /// This is safe to call concurrently with other calculations.
    public static func reset() {
        Astronomy_Reset()
    }
}

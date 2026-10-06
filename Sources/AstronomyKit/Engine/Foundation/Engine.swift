//
//  Engine.swift
//  AstronomyKit
//
//  Namespace and reference frames of the native Swift engine.
//

/// The native Swift astronomy engine.
///
/// Internal. The public API keeps calling the vendored C engine until the
/// native modules are complete. `NATIVE_ENGINE.md` at the repository root is
/// the design contract: file ownership, units, frames, time and Delta T model
/// ownership, errors, and cache lifetime.
enum Engine {}

// MARK: - Frames

extension Engine {
    /// The orientation of a vector's axes.
    ///
    /// Vector, state and rotation types take their frame as a type parameter,
    /// so a vector reaches another frame only through a ``Rotation``. The
    /// origin (Sun, barycenter, Earth, observer) is not part of the type; the
    /// function that returns a vector names it.
    protocol Frame {}

    /// Mean equator and equinox of J2000 (the C engine's EQJ).
    enum EQJ: Frame {}

    /// True equator and equinox of the vector's time (EQD).
    enum EQD: Frame {}

    /// Mean ecliptic and equinox of J2000 (ECL).
    enum ECL: Frame {}

    /// True ecliptic and equinox of the vector's time (ECT).
    enum ECT: Frame {}

    /// An observer's horizon: x north, y west, z zenith (HOR).
    enum HOR: Frame {}

    /// Galactic coordinates (GAL).
    enum GAL: Frame {}
}

//
//  EngineAtmosphere.swift
//  AstronomyKit
//
//  The 1976 U.S. Standard Atmosphere up to 100 km geopotential height.
//

import Foundation

extension Engine {
    /// Pressure in pascals, kinetic temperature in kelvins and density
    /// relative to sea level at one elevation, from the 1976 U.S. Standard
    /// Atmosphere (NOAA-S/T 76-1562).
    struct Atmosphere: Equatable, Sendable {
        var pressure: Double
        var temperature: Double
        var density: Double
    }
}

extension Engine.Atmosphere {
    // The standard's defining constants (table 2).
    private static let gravity = 9.806_65  // g0, m/s²
    private static let earthRadius = 6_356_766.0  // r0, m
    private static let molarMass = 28.964_4  // M0, kg/kmol
    private static let gasConstant = 8_314.32  // R*, J/(kmol·K)
    private static let avogadro = 6.022_169e26  // NA, 1/kmol
    private static let seaLevelPressure = 101_325.0  // Pa
    private static let seaLevelTemperature = 288.15  // K

    /// g0·M0/R*, in K/m: the hydrostatic constant of every layer below 86 km.
    private static let hydrostatic = gravity * molarMass / gasConstant
    /// The sea-level density P0·M0/(R*·T0), 1.2250 kg/m³.
    private static let seaLevelDensity = seaLevelPressure * molarMass / (gasConstant * seaLevelTemperature)

    /// The atmosphere at `elevation` metres of geopotential height
    /// (`Astronomy_Atmosphere`).
    ///
    /// Below 86 km geometric height (84,852 m geopotential) the model is the
    /// standard's seven layers in geopotential height (table 4), each
    /// starting from the pressure at the top of the one below, computed from
    /// the defining constants (#153). Above that the standard works in
    /// geometric height, and the engine integrates its diffusion equations
    /// for N2, O, O2, Ar and He. The temperature is the kinetic temperature
    /// throughout, which falls below the molecular-scale temperature between
    /// 80 and 86 km geometric height (table 8).
    ///
    /// - Throws: `AstronomyError.invalidParameter` for an elevation that is
    ///   not finite or is outside −500 to 100,000 m.
    init(elevation: Double) throws {
        guard (-500...100_000).contains(elevation) else {
            throw AstronomyError.invalidParameter
        }
        let z = Self.earthRadius * elevation / (Self.earthRadius - elevation)  // eq 19
        if z < Self.Upper.base {
            let layer = Self.layers.last { $0.base <= elevation } ?? Self.layers[0]
            let molecularTemperature = layer.molecularTemperature(at: elevation)
            pressure = layer.pressure(at: elevation)
            temperature = molecularTemperature * Self.molecularWeightRatio(geometricHeight: z)
            // The equation of state ρ = P·M0/(R*·TM), relative to sea level.
            density = (pressure / molecularTemperature) / (Self.seaLevelPressure / Self.seaLevelTemperature)
        } else {
            let n = Self.numberDensities(geometricHeight: z)
            temperature = Self.Upper.temperature(geometricHeight: z).kelvin
            pressure = n.sum() * Self.gasConstant * temperature / Self.avogadro  // eq 33c
            density = (n * Self.Upper.masses).sum() / Self.avogadro / Self.seaLevelDensity  // eq 42
        }
    }
}

// MARK: - Below 86 km

extension Engine.Atmosphere {
    /// One layer of table 4, in geopotential height, with the
    /// molecular-scale temperature and pressure at its base.
    private struct Layer {
        var base: Double  // m′
        var gradient: Double  // K/m′
        var baseTemperature: Double  // K
        var basePressure: Double  // Pa

        func molecularTemperature(at height: Double) -> Double {
            baseTemperature + gradient * (height - base)
        }

        /// Eq 33a, or eq 33b in an isothermal layer.
        func pressure(at height: Double) -> Double {
            let hydrostatic = Engine.Atmosphere.hydrostatic
            if gradient == 0 {
                return basePressure * exp(-hydrostatic / baseTemperature * (height - base))
            }
            return basePressure * pow(baseTemperature / molecularTemperature(at: height), hydrostatic / gradient)
        }
    }

    /// The layers of table 4: base geopotential height in m′ and the
    /// gradient of molecular-scale temperature in K/m′.
    private static let layers: [Layer] = {
        let gradients: [(base: Double, gradient: Double)] = [
            (0, -0.006_5), (11_000, 0), (20_000, 0.001), (32_000, 0.002_8), (47_000, 0), (51_000, -0.002_8),
            (71_000, -0.002),
        ]
        var layers: [Layer] = []
        for (base, gradient) in gradients {
            let below = layers.last
            layers.append(
                Layer(
                    base: base,
                    gradient: gradient,
                    baseTemperature: below?.molecularTemperature(at: base) ?? seaLevelTemperature,
                    basePressure: below?.pressure(at: base) ?? seaLevelPressure
                )
            )
        }
        return layers
    }()

    /// M/M0 at every 500 m of geometric height from 80 to 86 km (table 8).
    /// Kinetic temperature is the molecular-scale temperature times this
    /// ratio, so it reaches 186.8673 K at 86 km.
    private static let molecularWeightRatios = [
        1.000000, 0.999996, 0.999989, 0.999971, 0.999941, 0.999909, 0.999870, 0.999829, 0.999786, 0.999741,
        0.999694, 0.999641, 0.999579,
    ]

    /// Table 8's M/M0, interpolated linearly in geometric height, and 1 below
    /// 80 km.
    private static func molecularWeightRatio(geometricHeight z: Double) -> Double {
        let position = (z - 80_000) / 500
        guard position > 0 else { return 1 }
        let index = min(Int(position), molecularWeightRatios.count - 2)
        let fraction = position - Double(index)
        return molecularWeightRatios[index] + fraction
            * (molecularWeightRatios[index + 1] - molecularWeightRatios[index])
    }
}

// MARK: - From 86 km

extension Engine.Atmosphere {
    /// Number densities in m⁻³ of N2, O, O2, Ar and He, in that order, in the
    /// first five lanes; the other lanes are zero. Hydrogen, the standard's
    /// sixth species, starts at 150 km, above anything this model reaches.
    typealias Species = SIMD8<Double>

    /// The number densities at geometric height `z` metres, from 86 km up to
    /// about 101.6 km, the geometric height of 100 km geopotential.
    ///
    /// Each species follows eq 35: n = n₈₆·(T₈₆/T)·exp(−∫[f(Z) + v/(D + K)]dZ),
    /// with f(Z) from eq 36, the eddy diffusion K from eq 7, the molecular
    /// diffusion D from eq 8 and the flux term v/(D + K) from eq 37. N2
    /// has no flux term (eq 38). O and O2 diffuse through N2, and Ar and He
    /// through N2, O and O2 together. Up to 100 km the mean molecular weight
    /// in the mixing term is M0 for every species; above it, N2's is its own,
    /// O and O2 diffuse through N2's, and Ar and He through the mean of
    /// N2, O and O2.
    ///
    /// The engine integrates ln(n·T) with the classical fourth-order
    /// Runge-Kutta method in steps of at most `step` metres, restarting at
    /// 91, 95, 97 and 100 km, where the temperature profile, the eddy
    /// diffusion, the oxygen flux term and the molecular weight change form.
    /// With the default 100 m the densities move by at most 1e-10 when the
    /// step is halved.
    static func numberDensities(geometricHeight z: Double, step: Double = 100) -> Species {
        var logs = Species()
        var height = Upper.base
        for end in [91_000.0, 95_000, 97_000, 100_000].filter({ $0 < z }) + [z] where end > height {
            let count = ((end - height) / step).rounded(.up)
            let h = (end - height) / count
            let aboveMixing = height >= 100_000
            func slopes(_ logs: Species, _ z: Double) -> Species {
                Upper.slopes(logs, at: z, aboveMixing: aboveMixing)
            }
            for _ in 0..<Int(count) {
                let k1 = slopes(logs, height)
                let k2 = slopes(logs + h / 2 * k1, height + h / 2)
                let k3 = slopes(logs + h / 2 * k2, height + h / 2)
                let k4 = slopes(logs + h * k3, height + h)
                logs += h / 6 * (k1 + 2 * k2 + 2 * k3 + k4)
                height += h
            }
            height = end
        }
        return Upper.densities(logs, temperature: Upper.temperature(geometricHeight: z).kelvin)
    }

    /// The standard's model above 86 km, in geometric height.
    private enum Upper {
        /// Z7, the base of the region, in m.
        static let base = 86_000.0
        /// T7, the kinetic temperature from 86 to 91 km (eq 25).
        static let baseTemperature = 186.867_3

        // Table 3's molecular weights in kg/kmol and table 9's number
        // densities at 86 km in m⁻³.
        static let masses = Species(28.013_4, 15.999_4, 31.998_8, 39.948, 4.002_6, 0, 0, 0)
        static let baseDensities = Species(1.129_794e20, 8.6e16, 3.030_898e19, 1.351_400e18, 7.581_7e14, 0, 0, 0)

        /// The constants of one diffusing species, O, O2, Ar or He; eq 38
        /// for N2 needs none of them.
        struct Diffusion {
            var lane: Int
            var throughNitrogen: Bool  // O and O2 diffuse through N2 alone
            var thermalDiffusion: Double  // α (table 6)
            var scale: Double  // a, m⁻¹·s⁻¹ (table 6)
            var exponent: Double  // b (table 6)
            var flux: Flux  // Q, U and W (table 7)
            /// Atomic oxygen's second term, q·(u − Z)²·exp(−w·(u − Z)³) up to
            /// u = 97 km (table 7), written about u with decay −w.
            var lowFlux: Flux? = nil
        }

        /// One term of eq 37, in km: scale·(Z − centre)²·exp(−decay·(Z − centre)³).
        struct Flux {
            var scale: Double  // km⁻³
            var centre: Double  // km
            var decay: Double  // km⁻³

            func callAsFunction(kilometres z: Double) -> Double {
                let offset = z - centre
                return scale * offset * offset * exp(-decay * offset * offset * offset)
            }
        }

        static let diffusing = [
            Diffusion(
                lane: 1, throughNitrogen: true, thermalDiffusion: 0, scale: 6.986e20, exponent: 0.750,
                flux: Flux(scale: -5.809_644e-4, centre: 56.903_11, decay: 2.706_240e-5),
                lowFlux: Flux(scale: -3.416_248e-3, centre: 97, decay: -5.008_765e-4)
            ),
            Diffusion(
                lane: 2, throughNitrogen: true, thermalDiffusion: 0, scale: 4.863e20, exponent: 0.750,
                flux: Flux(scale: 1.366_212e-4, centre: 86, decay: 8.333_333e-5)
            ),
            Diffusion(
                lane: 3, throughNitrogen: false, thermalDiffusion: 0, scale: 4.487e20, exponent: 0.870,
                flux: Flux(scale: 9.434_079e-5, centre: 86, decay: 8.333_333e-5)
            ),
            Diffusion(
                lane: 4, throughNitrogen: false, thermalDiffusion: -0.40, scale: 1.700e21, exponent: 0.691,
                flux: Flux(scale: -2.457_369e-4, centre: 86, decay: 6.666_667e-4)
            ),
        ]

        /// The kinetic temperature in K and its gradient in K/m: isothermal
        /// to 91 km (eq 25), then the segment of an ellipse (eqs 27 and 28)
        /// that reaches 240 K at 110 km.
        static func temperature(geometricHeight z: Double) -> (kelvin: Double, gradient: Double) {
            guard z > 91_000 else { return (baseTemperature, 0) }
            let centre = 263.190_5  // Tc, K
            let amplitude = -76.323_2  // A, K
            let semiAxis = -19_942.9  // a, m
            let x = (z - 91_000) / semiAxis
            let root = (1 - x * x).squareRoot()
            return (centre + amplitude * root, -amplitude / semiAxis * x / root)
        }

        /// The eddy-diffusion coefficient K in m²/s (eqs 7a and 7b).
        static func eddyDiffusion(geometricHeight z: Double) -> Double {
            let k7 = 120.0
            guard z >= 95_000 else { return k7 }
            let kilometres = (z - 95_000) / 1_000
            return k7 * exp(1 - 400 / (400 - kilometres * kilometres))
        }

        /// The number densities that `logs` stands for, in the same lanes.
        static func densities(_ logs: Species, temperature: Double) -> Species {
            var n = Species()
            for lane in 0..<5 {
                n[lane] = baseDensities[lane] * baseTemperature / temperature * exp(logs[lane])
            }
            return n
        }

        /// The derivative of `logs` with geometric height, −[f(Z) + v/(D + K)]
        /// for each species (eqs 35, 36 and 38). `aboveMixing` selects the
        /// molecular weights that apply above 100 km.
        static func slopes(_ logs: Species, at z: Double, aboveMixing: Bool) -> Species {
            let (t, gradient) = temperature(geometricHeight: z)
            let ratio = earthRadius / (earthRadius + z)
            let g = gravity * ratio * ratio  // eq 17
            let n = densities(logs, temperature: t)
            let k = eddyDiffusion(geometricHeight: z)
            let gas = g / (gasConstant * t)
            let kilometres = z / 1_000
            let majors = n[0] + n[1] + n[2]
            // The molecular weights of N2 and of the N2, O and O2 mixture.
            let nitrogenMass = aboveMixing ? masses[0] : molarMass
            let majorMass = aboveMixing ? (n[0] * masses[0] + n[1] * masses[1] + n[2] * masses[2]) / majors : molarMass
            var slopes = Species()
            slopes[0] = -gas * nitrogenMass
            for species in diffusing {
                let background = species.throughNitrogen ? n[0] : majors
                let backgroundMass = species.throughNitrogen ? nitrogenMass : majorMass
                // Eq 8; its 273.15 K is a reference temperature, not a unit conversion.
                let d = species.scale / background * pow(t / 273.15, species.exponent)
                let f =
                    gas * d / (d + k)
                    * (masses[species.lane] + backgroundMass * k / d
                        + species.thermalDiffusion * gasConstant / g * gradient)
                var flux = species.flux(kilometres: kilometres)
                if let low = species.lowFlux, kilometres <= low.centre {
                    flux += low(kilometres: kilometres)
                }
                slopes[species.lane] = -(f + flux / 1_000)
            }
            return slopes
        }
    }
}

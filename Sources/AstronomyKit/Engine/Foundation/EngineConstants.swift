//
//  EngineConstants.swift
//  AstronomyKit
//
//  Numeric constants that more than one engine module uses.
//

extension Engine {
    /// Seconds in a day: 86,400 SI seconds, the day of every time scale the
    /// engine uses.
    static let secondsPerDay = 86_400.0

    /// Kilometers in one astronomical unit. IAU 2012 Resolution B2 defines
    /// the au as exactly 149,597,870,700 m.
    static let kilometersPerAU = 149_597_870.700

    /// The speed of light in AU per day: 299,792,458 m/s, exact in the SI,
    /// times 86,400 s, over the IAU 2012 au. Light crosses one au in
    /// 499.004 783 836 s.
    static let speedOfLightAUPerDay = 173.144_632_674_240_329_28

    /// π / 180.
    static let radiansPerDegree = 0.017_453_292_519_943_295_769_24

    /// 180 / π.
    static let degreesPerRadian = 57.295_779_513_082_320_876_80

    /// π / 12: radians in one hour of right ascension, sidereal time or hour
    /// angle.
    static let radiansPerHour = 0.261_799_387_799_149_436_538_55

    /// 12 / π.
    static let hoursPerRadian = 3.819_718_634_205_488_058_453_21

    /// π / 648,000.
    static let radiansPerArcsecond = 4.848_136_811_095_359_935_899_14e-6
}

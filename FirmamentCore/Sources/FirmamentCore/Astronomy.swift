import Foundation

/// Time and solar ephemeris formulas from Meeus, "Astronomical Algorithms" (2nd ed.).
/// Accuracy target is arcminutes: the low-precision solar ephemeris (ch. 25) is good
/// to ~0.5', and ΔT (UT vs. TT, a few arcseconds of solar longitude) is neglected.
public enum Astronomy {
    public static let astronomicalUnitKm = 149_597_870.7

    public static func julianDay(_ date: Date) -> Double {
        2_440_587.5 + date.timeIntervalSince1970 / 86_400
    }

    public static func julianCenturies(julianDay: Double) -> Double {
        (julianDay - 2_451_545.0) / 36_525
    }

    /// Greenwich mean sidereal time (Meeus 12.4), radians in [0, 2π).
    public static func gmstRadians(julianDay: Double) -> Double {
        let centuries = julianCenturies(julianDay: julianDay)
        let degrees = 280.460_618_37
            + 360.985_647_366_29 * (julianDay - 2_451_545.0)
            + 0.000_387_933 * centuries * centuries
            - centuries * centuries * centuries / 38_710_000
        return normalizedRadians(degrees * .pi / 180)
    }

    /// Mean obliquity of the ecliptic (Meeus 22.2), radians.
    public static func meanObliquityRadians(julianDay: Double) -> Double {
        let centuries = julianCenturies(julianDay: julianDay)
        let arcseconds = 21.448
            - 46.8150 * centuries
            - 0.000_59 * centuries * centuries
            + 0.001_813 * centuries * centuries * centuries
        let degrees = 23.0 + 26.0 / 60 + arcseconds / 3_600
        return degrees * .pi / 180
    }

    /// Sun's geometric ecliptic longitude referred to the mean equinox of date (Meeus ch. 25), degrees.
    public static func sunGeometricLongitudeDegrees(julianDay: Double) -> Double {
        let centuries = julianCenturies(julianDay: julianDay)
        let meanLongitude = 280.466_46 + 36_000.769_83 * centuries + 0.000_303_2 * centuries * centuries
        return meanLongitude + sunEquationOfCenterDegrees(julianDay: julianDay)
    }

    /// Sun-Earth distance (Meeus ch. 25), astronomical units.
    public static func sunDistanceAU(julianDay: Double) -> Double {
        let centuries = julianCenturies(julianDay: julianDay)
        let eccentricity = 0.016_708_634 - 0.000_042_037 * centuries - 0.000_000_126_7 * centuries * centuries
        let trueAnomalyDegrees = sunMeanAnomalyDegrees(julianDay: julianDay)
            + sunEquationOfCenterDegrees(julianDay: julianDay)
        let trueAnomaly = trueAnomalyDegrees * .pi / 180
        return 1.000_001_018 * (1 - eccentricity * eccentricity) / (1 + eccentricity * cos(trueAnomaly))
    }

    /// Sun's geocentric position in ecliptic-of-date rectangular coordinates, km.
    /// The sun's ecliptic latitude (< 1.2") is neglected.
    public static func sunGeocentricEclipticKm(julianDay: Double) -> Vector3 {
        let longitude = sunGeometricLongitudeDegrees(julianDay: julianDay) * .pi / 180
        let distanceKm = sunDistanceAU(julianDay: julianDay) * astronomicalUnitKm
        return Vector3(x: cos(longitude), y: sin(longitude), z: 0) * distanceKm
    }

    /// Earth's heliocentric position: the negation of the sun's geocentric position.
    public static func earthHeliocentricEclipticKm(julianDay: Double) -> Vector3 {
        -sunGeocentricEclipticKm(julianDay: julianDay)
    }

    public static func normalizedRadians(_ angle: Double) -> Double {
        let twoPi = 2 * Double.pi
        let remainder = angle.truncatingRemainder(dividingBy: twoPi)
        return remainder < 0 ? remainder + twoPi : remainder
    }

    private static func sunMeanAnomalyDegrees(julianDay: Double) -> Double {
        let centuries = julianCenturies(julianDay: julianDay)
        return 357.529_11 + 35_999.050_29 * centuries - 0.000_153_7 * centuries * centuries
    }

    private static func sunEquationOfCenterDegrees(julianDay: Double) -> Double {
        let centuries = julianCenturies(julianDay: julianDay)
        let meanAnomaly = sunMeanAnomalyDegrees(julianDay: julianDay) * .pi / 180
        return (1.914_602 - 0.004_817 * centuries - 0.000_014 * centuries * centuries) * sin(meanAnomaly)
            + (0.019_993 - 0.000_101 * centuries) * sin(2 * meanAnomaly)
            + 0.000_289 * sin(3 * meanAnomaly)
    }
}

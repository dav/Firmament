import Foundation
import Testing
@testable import FirmamentCore

/// Fixtures from worked examples in Meeus, "Astronomical Algorithms" (2nd ed.).
struct AstronomyTests {
    @Test func julianDayAtJ2000Epoch() {
        let j2000 = Date(timeIntervalSince1970: 946_728_000) // 2000-01-01T12:00:00Z
        #expect(Astronomy.julianDay(j2000) == 2_451_545.0)
    }

    @Test func julianDayMeeusExample() {
        // Meeus ex. 7.a adapted: 1987-04-10T00:00:00Z is JD 2446895.5.
        let date = utcDate(1987, 4, 10, 0, 0, 0)
        #expect(abs(Astronomy.julianDay(date) - 2_446_895.5) < 1e-9)
    }

    @Test func gmstMeeusExample12a() {
        // Meeus ex. 12.a: 1987-04-10 0h UT, GMST = 13h10m46.3668s = 197.693195°.
        let gmst = Astronomy.gmstRadians(julianDay: 2_446_895.5) * 180 / .pi
        #expect(abs(gmst - 197.693195) < 0.000_2)
    }

    @Test func gmstMeeusExample12b() {
        // Meeus ex. 12.b: 1987-04-10 19:21:00 UT, mean sidereal time = 128.737873°.
        let julianDay = Astronomy.julianDay(utcDate(1987, 4, 10, 19, 21, 0))
        let gmst = Astronomy.gmstRadians(julianDay: julianDay) * 180 / .pi
        #expect(abs(gmst - 128.737873) < 0.000_2)
    }

    @Test func obliquityMeeusExample22a() {
        // Meeus ex. 22.a: 1987-04-10, mean obliquity = 23°26'27.407" = 23.440946°.
        let obliquity = Astronomy.meanObliquityRadians(julianDay: 2_446_895.5) * 180 / .pi
        #expect(abs(obliquity - 23.440_946) < 0.000_1)
    }

    @Test func sunPositionMeeusExample25a() {
        // Meeus ex. 25.a: 1992-10-13 0h TD (JD 2448908.5):
        // geometric longitude 199.90988°, distance 0.99766 AU.
        let julianDay = 2_448_908.5
        let longitude = Astronomy.sunGeometricLongitudeDegrees(julianDay: julianDay)
            .truncatingRemainder(dividingBy: 360)
        let normalized = longitude < 0 ? longitude + 360 : longitude
        #expect(abs(normalized - 199.909_88) < 0.000_5)
        #expect(abs(Astronomy.sunDistanceAU(julianDay: julianDay) - 0.997_66) < 0.000_02)
    }

    @Test func earthHeliocentricOppositeSun() {
        let julianDay = 2_460_000.0
        let sun = Astronomy.sunGeocentricEclipticKm(julianDay: julianDay)
        let earth = Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        #expect((sun + earth).length < 1e-6)
        let distanceAU = sun.length / Astronomy.astronomicalUnitKm
        #expect(distanceAU > 0.97 && distanceAU < 1.04)
    }
}

// swiftlint:disable:next function_parameter_count
func utcDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    guard let date = calendar.date(from: components) else {
        fatalError("Invalid test date components")
    }
    return date
}

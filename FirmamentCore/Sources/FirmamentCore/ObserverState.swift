import Foundation

/// Everything about the observer needed to place lattice nodes in the local sky,
/// computed once per astronomy tick from UTC time and GPS coordinates.
public struct ObserverState: Sendable {
    public let date: Date
    public let latitudeDegrees: Double
    public let longitudeDegrees: Double
    public let altitudeMeters: Double
    public let gmstRadians: Double
    public let obliquityRadians: Double
    /// Observer's position relative to the Sun's center in the ecliptic-of-date inertial frame, km.
    public let heliocentricPositionKm: Vector3

    public init(date: Date, latitudeDegrees: Double, longitudeDegrees: Double, altitudeMeters: Double) {
        self.date = date
        self.latitudeDegrees = latitudeDegrees
        self.longitudeDegrees = longitudeDegrees
        self.altitudeMeters = altitudeMeters

        let julianDay = Astronomy.julianDay(date)
        let gmst = Astronomy.gmstRadians(julianDay: julianDay)
        let obliquity = Astronomy.meanObliquityRadians(julianDay: julianDay)
        gmstRadians = gmst
        obliquityRadians = obliquity

        let observerEcef = Geodesy.ecefKm(
            latitudeDegrees: latitudeDegrees,
            longitudeDegrees: longitudeDegrees,
            altitudeMeters: altitudeMeters
        )
        let earthHeliocentric = Astronomy.earthHeliocentricEclipticKm(julianDay: julianDay)
        let observerOffset = Frames.eclipticFromEcef(observerEcef, gmstRadians: gmst, obliquityRadians: obliquity)
        heliocentricPositionKm = earthHeliocentric + observerOffset
    }

    public var latitudeRadians: Double { latitudeDegrees * .pi / 180 }
    public var longitudeRadians: Double { longitudeDegrees * .pi / 180 }
}

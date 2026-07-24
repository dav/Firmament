import Foundation

/// WGS84 geodetic-to-ECEF conversion.
public enum Geodesy {
    public static let equatorialRadiusKm = 6_378.137
    public static let flattening = 1 / 298.257_223_563
    public static let meanDiameterKm = 12_742.0

    public static func ecefKm(latitudeDegrees: Double, longitudeDegrees: Double, altitudeMeters: Double) -> Vector3 {
        let latitude = latitudeDegrees * .pi / 180
        let longitude = longitudeDegrees * .pi / 180
        let altitudeKm = altitudeMeters / 1_000
        let eccentricitySquared = flattening * (2 - flattening)
        let sinLatitude = sin(latitude)
        let primeVerticalRadius = equatorialRadiusKm
            / (1 - eccentricitySquared * sinLatitude * sinLatitude).squareRoot()
        return Vector3(
            x: (primeVerticalRadius + altitudeKm) * cos(latitude) * cos(longitude),
            y: (primeVerticalRadius + altitudeKm) * cos(latitude) * sin(longitude),
            z: (primeVerticalRadius * (1 - eccentricitySquared) + altitudeKm) * sinLatitude
        )
    }
}

import Foundation

/// A plain-value GPS fix, decoupled from CoreLocation types.
struct GeoFix: Equatable, Sendable {
    var latitudeDegrees: Double
    var longitudeDegrees: Double
    var altitudeMeters: Double
    var horizontalAccuracyMeters: Double
    var timestamp: Date
}

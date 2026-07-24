import Foundation

/// Rotations between the Earth-fixed (ECEF), equatorial inertial, and
/// ecliptic-of-date inertial frames, plus the local East-North-Up basis.
public enum Frames {
    /// Active rotation about the z-axis by `angle` radians.
    public static func rotatedAboutZ(_ vector: Vector3, by angle: Double) -> Vector3 {
        Vector3(
            x: vector.x * cos(angle) - vector.y * sin(angle),
            y: vector.x * sin(angle) + vector.y * cos(angle),
            z: vector.z
        )
    }

    /// Active rotation about the x-axis by `angle` radians.
    public static func rotatedAboutX(_ vector: Vector3, by angle: Double) -> Vector3 {
        Vector3(
            x: vector.x,
            y: vector.y * cos(angle) - vector.z * sin(angle),
            z: vector.y * sin(angle) + vector.z * cos(angle)
        )
    }

    public static func eclipticFromEcef(_ ecef: Vector3, gmstRadians: Double, obliquityRadians: Double) -> Vector3 {
        let equatorialInertial = rotatedAboutZ(ecef, by: gmstRadians)
        return rotatedAboutX(equatorialInertial, by: -obliquityRadians)
    }

    public static func ecefFromEcliptic(_ ecliptic: Vector3, gmstRadians: Double, obliquityRadians: Double) -> Vector3 {
        let equatorialInertial = rotatedAboutX(ecliptic, by: obliquityRadians)
        return rotatedAboutZ(equatorialInertial, by: -gmstRadians)
    }

    /// The local "up" direction expressed in the ECEF frame.
    public static func enuInverseUp(latitudeRadians: Double, longitudeRadians: Double) -> Vector3 {
        Vector3(
            x: cos(latitudeRadians) * cos(longitudeRadians),
            y: cos(latitudeRadians) * sin(longitudeRadians),
            z: sin(latitudeRadians)
        )
    }

    /// Components of an ECEF-frame vector in the local East-North-Up basis
    /// at the given geodetic latitude/longitude. Returned as (x: east, y: north, z: up).
    public static func enuComponents(
        ofEcef vector: Vector3,
        latitudeRadians: Double,
        longitudeRadians: Double
    ) -> Vector3 {
        let sinLat = sin(latitudeRadians)
        let cosLat = cos(latitudeRadians)
        let sinLon = sin(longitudeRadians)
        let cosLon = cos(longitudeRadians)
        return Vector3(
            x: -sinLon * vector.x + cosLon * vector.y,
            y: -sinLat * cosLon * vector.x - sinLat * sinLon * vector.y + cosLat * vector.z,
            z: cosLat * cosLon * vector.x + cosLat * sinLon * vector.y + sinLat * vector.z
        )
    }
}

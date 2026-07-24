import Foundation

/// A double-precision 3D vector. Units are kilometers unless noted otherwise.
public struct Vector3: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var z: Double

    public init(x: Double, y: Double, z: Double) {
        self.x = x
        self.y = y
        self.z = z
    }

    public static let zero = Vector3(x: 0, y: 0, z: 0)

    public var length: Double {
        (x * x + y * y + z * z).squareRoot()
    }

    public var normalized: Vector3 {
        let magnitude = length
        guard magnitude > 0 else { return .zero }
        return self * (1 / magnitude)
    }

    public func dot(_ other: Vector3) -> Double {
        x * other.x + y * other.y + z * other.z
    }

    public static func + (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    public static func - (lhs: Vector3, rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    public static prefix func - (value: Vector3) -> Vector3 {
        Vector3(x: -value.x, y: -value.y, z: -value.z)
    }

    public static func * (lhs: Vector3, rhs: Double) -> Vector3 {
        Vector3(x: lhs.x * rhs, y: lhs.y * rhs, z: lhs.z * rhs)
    }
}

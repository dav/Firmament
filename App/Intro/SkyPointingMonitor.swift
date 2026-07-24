import RealityKit
import simd

/// Reads "is the camera pointed at the sky" straight from the AR camera
/// transform — the world frame is gravity-aligned, so the forward vector's
/// y-component is the pointing elevation. No CoreMotion needed.
nonisolated enum SkyPointingMonitor {
    /// Camera pointing elevation above the horizon, in degrees.
    static func cameraElevationDegrees(_ transform: Transform) -> Float {
        let forward = cameraForward(transform)
        return asin(min(max(forward.y, -1), 1)) * 180 / .pi
    }

    /// The camera looks down its local -z axis.
    static func cameraForward(_ transform: Transform) -> SIMD3<Float> {
        let column = transform.matrix.columns.2
        return -SIMD3(column.x, column.y, column.z)
    }
}

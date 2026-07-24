import simd

/// A world-space camera pose the meld drives the tour's virtual camera with.
nonisolated struct MeldCameraPose: Sendable {
    let position: SIMD3<Float>
    let rotation: simd_quatf
    let fovDegrees: Float
}

import simd

/// Easing applied while interpolating INTO a keyframe or across an action's
/// progress range.
nonisolated enum TourEasing: Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    /// Maps linear progress 0...1 onto the eased curve (cubic).
    func apply(_ x: Double) -> Double {
        let t = min(max(x, 0), 1)
        switch self {
        case .linear:
            return t
        case .easeIn:
            return t * t * t
        case .easeOut:
            let inverse = 1 - t
            return 1 - inverse * inverse * inverse
        case .easeInOut:
            if t < 0.5 {
                return 4 * t * t * t
            }
            let inverse = -2 * t + 2
            return 1 - inverse * inverse * inverse / 2
        }
    }
}

/// The reference frame a keyframe's position/lookAt are authored in. The scene
/// controller resolves each frame to a world pose at sample time; interpolating
/// between keyframes in *different* frames blends the resolved world poses,
/// which is how the camera hands over between the car, the Earth, and the
/// user's home point without a cut.
nonisolated enum CameraFrameRef: Sendable {
    /// Tour world root. Sun sits at the origin in the space scene.
    case world
    /// Follows the race car: origin at the car, -z its forward, +y up.
    case car
    /// Tracks the Earth continuously: origin at Earth's center, -z toward the
    /// sun, +y ecliptic north.
    case earth
    /// The `earth` frame frozen at the current beat's start time — the camera
    /// stays fixed in space while the Earth sails on past.
    case earthAtBeatStart
    /// The device's location on the stylized Earth: origin at the surface
    /// point, +y the local zenith, -z the local north tangent.
    case home
}

nonisolated struct CameraKeyframe: Sendable {
    /// Position within the beat, 0...1.
    let progress: Double
    let frame: CameraFrameRef
    let position: SIMD3<Float>
    let lookAt: SIMD3<Float>
    let fovDegrees: Float
    /// Easing used while interpolating from the previous keyframe to this one.
    let easing: TourEasing

    init(
        progress: Double,
        frame: CameraFrameRef,
        position: SIMD3<Float>,
        lookAt: SIMD3<Float>,
        fovDegrees: Float,
        easing: TourEasing = .easeInOut
    ) {
        self.progress = progress
        self.frame = frame
        self.position = position
        self.lookAt = lookAt
        self.fovDegrees = fovDegrees
        self.easing = easing
    }
}

/// A sampled camera state: the bracketing keyframes and the eased blend
/// between them. The scene controller resolves both endpoints to world poses
/// (through their reference frames) and interpolates there, so cross-frame
/// keyframe pairs melt one frame into another.
nonisolated struct SampledCamera: Sendable {
    let from: CameraKeyframe
    let to: CameraKeyframe
    /// Eased blend 0...1 from `from` to `to`.
    let blend: Double

    var fovDegrees: Float {
        from.fovDegrees + (to.fovDegrees - from.fovDegrees) * Float(blend)
    }
}

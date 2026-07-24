import simd

/// Pure pose math for the tour: rig positions as closed-form functions of tour
/// time, so any instant can be reconstructed exactly when scrubbing.
nonisolated enum TourMath {
    /// Orientation with -z along `forward` and +y as near `up` as possible.
    /// When `forward` is (nearly) parallel to `up` — e.g. the final tour pose
    /// looking straight up the local zenith — the roll would otherwise be
    /// resolved from float noise and jitter frame to frame; `fallbackUp`
    /// provides a stable roll reference for that case.
    static func lookRotation(
        forward: SIMD3<Float>,
        up: SIMD3<Float>,
        fallbackUp: SIMD3<Float>? = nil
    ) -> simd_quatf {
        let zForward = simd_normalize(forward)
        var upHint = up
        if let fallbackUp, abs(simd_dot(simd_normalize(up), zForward)) > 0.99 {
            upHint = fallbackUp
        }
        var yAxis = upHint - simd_dot(upHint, zForward) * zForward
        if simd_length_squared(yAxis) < 1e-9 {
            let fallback: SIMD3<Float> = abs(zForward.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
            yAxis = fallback - simd_dot(fallback, zForward) * zForward
        }
        yAxis = simd_normalize(yAxis)
        let xAxis = simd_normalize(simd_cross(zForward, yAxis))
        let zAxis = -zForward
        return simd_quatf(simd_float3x3(columns: (xAxis, simd_cross(zAxis, xAxis), zAxis)))
    }

    /// Point on a y-up circle, mapped so that increasing angle sweeps
    /// counter-clockwise when viewed from +y — matching the real Earth's
    /// prograde orbit as seen from ecliptic north. Every circular path in the
    /// tour (car track, orbit, orbit draw-on, node reveal center) goes through
    /// this one mapping so their tuned angles stay mutually consistent.
    static func circlePoint(radius: Float, angle: Float) -> SIMD3<Float> {
        SIMD3(radius * cos(angle), 0, -radius * sin(angle))
    }

    /// Unit direction of travel at `angle` for motion along `circlePoint`
    /// with increasing angle.
    static func circleTangent(angle: Float) -> SIMD3<Float> {
        SIMD3(-sin(angle), 0, -cos(angle))
    }

    /// Orientation aligning a lattice cube with the stylized space scene's
    /// axes, mirroring how the live sky aligns cubes to the real ecliptic
    /// frame: cube-local +x (the vernal-equinox face) along scene +x, +z
    /// (ecliptic north) up along scene +y, and +y (June solstice) along
    /// scene −z — 90° ahead along the counter-clockwise orbit.
    static let latticeCubeOrientation = simd_quatf(simd_float3x3(columns: (
        SIMD3<Float>(1, 0, 0),
        SIMD3<Float>(0, 0, -1),
        SIMD3<Float>(0, 1, 0)
    )))

    /// The car's angle around the track at tour time `t`.
    static func carAngle(at t: Double) -> Float {
        Float(t / TourTuning.carLapDuration) * 2 * .pi
    }

    /// Car pose on the track circle: origin at the car, -z its forward
    /// (direction of travel), +y up.
    static func carTransform(at t: Double) -> simd_float4x4 {
        let angle = carAngle(at: t)
        let position = circlePoint(radius: TourTuning.trackRadius, angle: angle)
        let rotation = lookRotation(forward: circleTangent(angle: angle), up: [0, 1, 0])
        return transformMatrix(rotation: rotation, translation: position)
    }

    /// Earth's angle along the stylized orbit at tour time `t`.
    static func earthAngle(at t: Double) -> Float {
        TourTuning.earthStartAngle + Float(t / TourTuning.earthOrbitPeriod) * 2 * .pi
    }

    /// Earth's center position in space-scene coordinates (sun at the origin).
    static func earthPosition(at t: Double) -> SIMD3<Float> {
        circlePoint(radius: TourTuning.orbitRadius, angle: earthAngle(at: t))
    }

    /// The stylized globe's orientation at time `t`: a fixed axial tilt with a
    /// fast prograde spin about the tilted pole (counter-clockwise from above,
    /// like the orbit). Pure function of time, so scrubbing stays exact.
    static func earthSpinOrientation(at t: Double) -> simd_quatf {
        let tilt = simd_quatf(angle: TourTuning.earthAxialTiltDegrees * .pi / 180, axis: [0, 0, 1])
        let spinAngle = Float(t / TourTuning.earthSpinSecondsPerRevolution) * 2 * .pi
        let spin = simd_quatf(angle: spinAngle, axis: [0, 1, 0])
        return tilt * spin
    }

    /// Earth frame: origin at Earth's center, -z toward the sun, +y ecliptic
    /// north.
    static func earthTransform(at t: Double) -> simd_float4x4 {
        let position = earthPosition(at: t)
        let rotation = lookRotation(forward: -simd_normalize(position), up: [0, 1, 0])
        return transformMatrix(rotation: rotation, translation: position)
    }

    /// Direction to a latitude/longitude on the unit sphere, in the Earth
    /// entity's local coordinates. Longitude winds westward around -z so the
    /// mapping matches the equirectangular texture applied in the builder.
    static func sphereDirection(latitudeDegrees: Double, longitudeDegrees: Double) -> SIMD3<Float> {
        let latitude = Float(latitudeDegrees * .pi / 180)
        let longitude = Float(longitudeDegrees * .pi / 180)
        return SIMD3(
            cos(latitude) * cos(longitude),
            sin(latitude),
            -cos(latitude) * sin(longitude)
        )
    }

    /// Home frame on the stylized Earth: origin at the surface point, +y the
    /// local zenith, -z the local north tangent. `earthMatrix` is the Earth
    /// entity's world transform at the same instant.
    static func homeTransform(
        earthMatrix: simd_float4x4,
        latitudeDegrees: Double,
        longitudeDegrees: Double,
        earthRadius: Float
    ) -> simd_float4x4 {
        let localUp = sphereDirection(latitudeDegrees: latitudeDegrees, longitudeDegrees: longitudeDegrees)
        let localPosition = localUp * earthRadius
        let worldUp = simd_normalize(rotate(earthMatrix, localUp))
        let worldPosition = transform(earthMatrix, localPosition)
        var north = SIMD3<Float>(rotate(earthMatrix, [0, 1, 0]))
        north -= simd_dot(north, worldUp) * worldUp
        if simd_length_squared(north) < 1e-9 {
            north = simd_cross(worldUp, [1, 0, 0])
        }
        north = simd_normalize(north)
        let rotation = lookRotation(forward: north, up: worldUp)
        return transformMatrix(rotation: rotation, translation: worldPosition)
    }

    static func transformMatrix(rotation: simd_quatf, translation: SIMD3<Float>) -> simd_float4x4 {
        var matrix = simd_float4x4(rotation)
        matrix.columns.3 = SIMD4(translation, 1)
        return matrix
    }

    /// Applies the full transform (rotation + translation) to a point.
    static func transform(_ matrix: simd_float4x4, _ point: SIMD3<Float>) -> SIMD3<Float> {
        let result = matrix * SIMD4(point, 1)
        return SIMD3(result.x, result.y, result.z)
    }

    /// Applies only the rotation part of a transform to a direction.
    static func rotate(_ matrix: simd_float4x4, _ direction: SIMD3<Float>) -> SIMD3<Float> {
        let result = matrix * SIMD4(direction, 0)
        return SIMD3(result.x, result.y, result.z)
    }

    static func mix(_ start: SIMD3<Float>, _ end: SIMD3<Float>, _ fraction: Float) -> SIMD3<Float> {
        start + (end - start) * fraction
    }
}

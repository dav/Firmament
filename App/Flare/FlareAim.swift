import Foundation
import simd

/// How far the camera is from the spot a flare dropped now would fall to, and
/// what the user has to do about it.
///
/// Pure value math on the AR world frame (+x east, +y up, +z south), so the
/// whole guidance decision is unit-testable without a live AR session.
nonisolated struct FlareAim: Sendable, Equatable {
    /// The camera must be within this of the drop point before the flare button
    /// arms — comfortably inside the phone's field of view, so the flare is on
    /// screen from the moment it appears.
    static let onTargetRadians = 15 * Double.pi / 180
    /// Hysteresis: once armed, the camera has to drift this far before it
    /// disarms, so a shaky hand can't flicker the button on the boundary.
    static let offTargetRadians = 20 * Double.pi / 180
    /// Corrections smaller than this are noise, not guidance.
    static let instructionThresholdRadians = 3 * Double.pi / 180

    /// Shortest signed turn onto the target, radians. Positive means turn right.
    let yawRadians: Double
    /// Signed tilt onto the target, radians. Positive means raise the phone.
    let pitchRadians: Double
    /// Great-circle angle between the camera axis and the target, radians.
    let offsetRadians: Double
    /// The target's elevation above the local horizon, radians.
    let targetElevationRadians: Double

    init(target: FlareDropTarget, cameraForward: SIMD3<Float>) {
        let forward = Self.normalizedForward(cameraForward)
        let cameraElevation = asin(min(max(forward.y, -1), 1))
        let cameraAzimuth = atan2(forward.x, -forward.z)

        yawRadians = Self.shortestSignedAngle(from: cameraAzimuth, to: target.azimuthRadians)
        pitchRadians = target.elevationRadians - cameraElevation
        let targetVector = Self.unitVector(
            azimuthRadians: target.azimuthRadians,
            elevationRadians: target.elevationRadians
        )
        offsetRadians = acos(min(max(simd_dot(targetVector, forward), -1), 1))
        targetElevationRadians = target.elevationRadians
    }

    /// Whether the camera is pointed close enough to drop. Callers holding a
    /// previous verdict should use `FlareAimModel`, which adds hysteresis.
    var isOnTarget: Bool { offsetRadians <= Self.onTargetRadians }

    /// The drop point is behind the Earth, so the lattice's horizon occlusion
    /// would swallow the flare along with the nodes around it.
    var isBelowHorizon: Bool { targetElevationRadians < 0 }

    /// The user must switch occlusion off before the flare would be watchable.
    func needsXRay(showBelowHorizon: Bool) -> Bool {
        isBelowHorizon && !showBelowHorizon
    }

    /// The turn-and-tilt steps left, in the order they read naturally. Empty
    /// once both axes are within noise of the target.
    var instructions: [FlareAimInstruction] {
        var steps: [FlareAimInstruction] = []
        if abs(yawRadians) >= Self.instructionThresholdRadians {
            steps.append(FlareAimInstruction(
                systemImage: yawRadians > 0 ? "arrow.turn.up.right" : "arrow.turn.up.left",
                text: "Turn \(yawRadians > 0 ? "right" : "left") \(Self.degrees(abs(yawRadians)))°"
            ))
        }
        if abs(pitchRadians) >= Self.instructionThresholdRadians {
            steps.append(FlareAimInstruction(
                systemImage: pitchRadians > 0 ? "arrow.up" : "arrow.down",
                text: "Tilt \(pitchRadians > 0 ? "up" : "down") \(Self.degrees(abs(pitchRadians)))°"
            ))
        }
        return steps
    }

    private static func degrees(_ radians: Double) -> Int {
        Int((radians * 180 / .pi).rounded())
    }

    /// Signed difference in [-π, π], so the guidance always names the short way
    /// around rather than sending the user 300° the wrong way.
    private static func shortestSignedAngle(from: Double, to: Double) -> Double {
        atan2(sin(to - from), cos(to - from))
    }

    private static func unitVector(azimuthRadians: Double, elevationRadians: Double) -> SIMD3<Double> {
        let cosElevation = cos(elevationRadians)
        return SIMD3(
            sin(azimuthRadians) * cosElevation,
            sin(elevationRadians),
            -cos(azimuthRadians) * cosElevation
        )
    }

    /// Falls back to due north when handed a degenerate vector — the camera
    /// transform before ARKit has a pose to report.
    private static func normalizedForward(_ vector: SIMD3<Float>) -> SIMD3<Double> {
        let doubled = SIMD3<Double>(Double(vector.x), Double(vector.y), Double(vector.z))
        let length = simd_length(doubled)
        guard length > 0 else { return SIMD3(0, 0, -1) }
        return doubled / length
    }
}

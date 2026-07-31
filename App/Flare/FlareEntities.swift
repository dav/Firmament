import RealityKit
import UIKit

/// The dropped flare's entities: the sphere itself and the distance label that
/// trails under it. Grouped in one object so `SkyDomeScene` can add and drop the
/// whole thing in a single move.
///
/// The label is a text mesh rather than screen chrome so it travels with the
/// flare — turn around and the number is still hanging there. It faces the
/// camera by construction: the dome anchor rides the camera, so "toward the
/// camera" is just "toward the anchor origin", which costs one quaternion per
/// tick instead of per-frame billboarding.
@MainActor
final class FlareEntities {
    /// Text mesh nominal size. The label's own scale stretches this to a
    /// constant on-screen height, so the value only sets the glyph resolution.
    nonisolated static let labelFontSize: CGFloat = 0.1

    /// Hot magenta: unclaimed by any cube face, the sun, or the plane markers,
    /// so the flare never reads as part of the lattice.
    private static let flareColor = UIColor(red: 1, green: 0.13, blue: 0.7, alpha: 1)

    let root = Entity()

    private let ball = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [])
    private let label = Entity()
    private let labelMesh = ModelEntity()
    private var appliedText: String?
    private var appliedGhosting: Bool?

    init() {
        ball.name = "flare"
        label.addChild(labelMesh)
        root.addChild(ball)
        root.addChild(label)
    }

    /// Applies one tick. `isNew` snaps the flare into place instead of animating
    /// it in from the origin.
    func apply(_ placement: FlarePlacement, animationDuration: TimeInterval, isNew: Bool) {
        root.isEnabled = !placement.isHidden
        applyGhosting(placement.isBelowHorizon)
        applyLabelText(distanceKm: placement.distanceKm)

        if isNew {
            ball.transform = Transform(
                scale: SIMD3(repeating: placement.nowDiameter),
                translation: placement.nowPosition
            )
        }
        ball.move(
            to: Transform(
                scale: SIMD3(repeating: placement.targetDiameter),
                translation: placement.targetPosition
            ),
            relativeTo: root,
            duration: animationDuration,
            timingFunction: .linear
        )

        label.transform = Transform(
            scale: SIMD3(repeating: placement.labelScale),
            rotation: Self.orientationFacingAnchorOrigin(from: placement.labelPosition),
            translation: placement.labelPosition
        )
    }

    /// Below the horizon the flare is behind the planet, so it takes the same
    /// ghost treatment as the lattice nodes rather than vanishing — it is the
    /// user's own marker, and losing it entirely reads as a bug.
    private func applyGhosting(_ isGhost: Bool) {
        guard appliedGhosting != isGhost else { return }
        appliedGhosting = isGhost
        ball.model?.materials = [Self.material(color: Self.flareColor, isGhost: isGhost)]
        labelMesh.model?.materials = [Self.material(color: .white, isGhost: isGhost)]
    }

    private func applyLabelText(distanceKm: Double) {
        let text = FlareDistanceText.kilometers(distanceKm)
        guard appliedText != text else { return }
        appliedText = text

        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.002,
            font: .systemFont(ofSize: Self.labelFontSize, weight: .semibold),
            alignment: .center
        )
        labelMesh.model = ModelComponent(
            mesh: mesh,
            materials: [Self.material(color: .white, isGhost: appliedGhosting ?? false)]
        )
        // Generated text starts at the baseline origin and runs right; recenter
        // it so the label's own pivot is what gets aimed at the camera.
        labelMesh.position = -mesh.bounds.center
    }

    private static func material(color: UIColor, isGhost: Bool) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        if isGhost {
            material.blending = .transparent(opacity: .init(floatLiteral: SkyRenderer.ghostOpacity))
        }
        return material
    }

    /// Turns the label's +z toward the dome anchor's origin — which is where the
    /// camera always sits, since `SkyDomeScene` parks the anchor on it.
    private static func orientationFacingAnchorOrigin(from position: SIMD3<Float>) -> simd_quatf {
        let forward = normalize(-position)
        let worldUp = SIMD3<Float>(0, 1, 0)
        let sideways = cross(worldUp, forward)
        let right = length(sideways) > 1e-4 ? normalize(sideways) : SIMD3<Float>(1, 0, 0)
        return simd_quatf(simd_float3x3(columns: (right, cross(forward, right), forward)))
    }
}

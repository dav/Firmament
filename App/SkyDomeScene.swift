import FirmamentCore
import RealityKit
import SwiftUI

/// The dome's entity pool: node cubes, edge outlines, grid lines, and the sun,
/// all parented to a camera-centered anchor. Extracted from `SkyRenderer` so
/// the same `SkyFrame` can be applied to two scenes at once — the live AR view
/// and the intro tour's virtual-camera view render identical domes during the
/// tour-to-AR meld.
@MainActor
final class SkyDomeScene {
    let skyAnchor = AnchorEntity(world: .zero)
    let linesEntity = ModelEntity()
    var entities: [LatticeNode: ModelEntity] = [:]
    var nodeStyles: [LatticeNode: NodeStyle] = [:]
    var materialCache: [NodeStyle: [UnlitMaterial]] = [:]
    var appliedFaceColors: [Color.Resolved] = []
    private let cubeMesh = CubeMesh.make()
    private let edgesMesh = CubeEdgesMesh.make()
    private let sunEntity: ModelEntity
    private var edgeEntities: [LatticeNode: ModelEntity] = [:]
    private var flareEntities: FlareEntities?

    init() {
        var sunMaterial = UnlitMaterial(color: .systemOrange)
        sunMaterial.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        sunEntity = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [sunMaterial])
    }

    func attach(to scene: RealityKit.Scene) {
        scene.addAnchor(skyAnchor)
    }

    func detach() {
        skyAnchor.removeFromParent()
    }

    /// Applies a precomputed frame to the entity pool. Cheap main-actor work
    /// only: pool bookkeeping, transform animations, material/mesh assignment.
    func apply(
        _ frame: SkyFrame,
        faceColors: [Color.Resolved],
        cameraTranslation: SIMD3<Float>,
        animationDuration: TimeInterval
    ) {
        rebuildMaterialsIfNeeded(faceColors: faceColors)
        skyAnchor.position = cameraTranslation

        var currentNodes = Set<LatticeNode>()
        currentNodes.reserveCapacity(frame.placements.count)
        for placement in frame.placements {
            currentNodes.insert(placement.node)
            let isNew = entities[placement.node] == nil
            let entity = entities[placement.node] ?? addEntity(for: placement.node)
            applyStyle(placement.style, to: entity, node: placement.node)

            if isNew {
                entity.transform = Transform(
                    scale: SIMD3(repeating: placement.nowScale),
                    rotation: frame.latticeOrientation,
                    translation: placement.nowPosition
                )
            }
            let target = Transform(
                scale: SIMD3(repeating: placement.targetScale),
                rotation: frame.latticeOrientation,
                translation: placement.targetPosition
            )
            entity.move(to: target, relativeTo: skyAnchor, duration: animationDuration, timingFunction: .linear)
        }
        for (node, entity) in entities where !currentNodes.contains(node) {
            entity.removeFromParent()
            entities[node] = nil
            edgeEntities[node] = nil
            nodeStyles[node] = nil
        }

        applyLines(frame)
        applyFlare(frame.flare, animationDuration: animationDuration)

        sunEntity.position = frame.sunPosition
        sunEntity.scale = SIMD3(repeating: frame.sunScale)
        if sunEntity.parent == nil {
            skyAnchor.addChild(sunEntity)
        }
    }

    /// Adds, updates, or tears down the dropped flare. A nil placement covers
    /// both "no flare" and "just dropped, not yet clear of the observer".
    private func applyFlare(_ placement: FlarePlacement?, animationDuration: TimeInterval) {
        guard let placement else {
            flareEntities?.root.removeFromParent()
            flareEntities = nil
            return
        }
        let isNew = flareEntities == nil
        let flare = flareEntities ?? FlareEntities()
        if isNew {
            flareEntities = flare
            skyAnchor.addChild(flare.root)
        }
        flare.apply(placement, animationDuration: animationDuration, isNew: isNew)
    }

    private func addEntity(for node: LatticeNode) -> ModelEntity {
        let entity = ModelEntity(mesh: cubeMesh, materials: [])
        entity.name = "(\(node.i), \(node.j), \(node.k))"
        skyAnchor.addChild(entity)
        entities[node] = entity
        return entity
    }

    private func applyStyle(_ style: NodeStyle, to entity: ModelEntity, node: LatticeNode) {
        guard nodeStyles[node] != style else { return }
        nodeStyles[node] = style
        entity.model?.materials = materials(for: style)
        setEdgeOutline(on: entity, node: node, visible: style.isOnEclipticPlane)
    }

    private func setEdgeOutline(on entity: ModelEntity, node: LatticeNode, visible: Bool) {
        if visible {
            guard edgeEntities[node] == nil else { return }
            let edges = ModelEntity(mesh: edgesMesh, materials: [Self.edgeMaterial])
            entity.addChild(edges)
            edgeEntities[node] = edges
        } else if let edges = edgeEntities[node] {
            edges.removeFromParent()
            edgeEntities[node] = nil
        }
    }
}

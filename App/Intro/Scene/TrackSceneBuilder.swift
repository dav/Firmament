import RealityKit
import UIKit

/// Builds the race-track scene for beats 1–4: grass, a circular pavement ring,
/// painted edge lines, trackside posts, and the car itself. Flat unlit colors
/// throughout — the 3Blue1Brown look.
@MainActor
enum TrackSceneBuilder {
    private static let grassColor = UIColor(red: 0.13, green: 0.28, blue: 0.16, alpha: 1)
    private static let pavementColor = UIColor(red: 0.11, green: 0.11, blue: 0.12, alpha: 1)
    private static let lineColor = UIColor.white
    private static let postColor = UIColor(white: 0.85, alpha: 1)
    private static let carBodyColor = UIColor(red: 0.23, green: 0.42, blue: 0.84, alpha: 1)
    private static let carCabinColor = UIColor(red: 0.10, green: 0.15, blue: 0.24, alpha: 1)

    /// Vertical stacking to avoid z-fighting between coplanar rings.
    private static let grassY: Float = -0.03
    private static let lineY: Float = 0.02

    /// Builds all track entities under `trackRoot` (static scenery) and
    /// `carRig` (follows the car), returning the fade/action target groups.
    static func build(trackRoot: Entity, carRig: Entity) -> [TourEntityID: Entity] {
        var groups: [TourEntityID: Entity] = [:]
        groups[.grass] = makeGrass(under: trackRoot)
        groups[.trackPavement] = makePavement(under: trackRoot)
        groups[.trackEdgeLines] = makeEdgeLines(under: trackRoot)
        groups[.posts] = makePosts(under: trackRoot)
        groups[.car] = makeCar(under: carRig)
        groups[.ornamentGlobe] = makeOrnamentGlobe(under: carRig)
        return groups
    }

    private static func flatMaterial(_ color: UIColor) -> UnlitMaterial {
        var material = UnlitMaterial(color: color)
        material.faceCulling = .none
        return material
    }

    private static func makeGrass(under parent: Entity) -> Entity {
        let group = Entity()
        group.name = "grass"
        let innerEdge = TourTuning.trackRadius - TourTuning.trackHalfWidth
        let outerEdge = TourTuning.trackRadius + TourTuning.trackHalfWidth
        let infield = ModelEntity(
            mesh: RingMesh.make(innerRadius: 0, outerRadius: innerEdge),
            materials: [flatMaterial(grassColor)]
        )
        let outfield = ModelEntity(
            mesh: RingMesh.make(innerRadius: outerEdge, outerRadius: TourTuning.grassRadius),
            materials: [flatMaterial(grassColor)]
        )
        group.addChild(infield)
        group.addChild(outfield)
        group.position.y = grassY
        parent.addChild(group)
        return group
    }

    private static func makePavement(under parent: Entity) -> Entity {
        let pavement = ModelEntity(
            mesh: RingMesh.make(
                innerRadius: TourTuning.trackRadius - TourTuning.trackHalfWidth,
                outerRadius: TourTuning.trackRadius + TourTuning.trackHalfWidth
            ),
            materials: [flatMaterial(pavementColor)]
        )
        pavement.name = "pavement"
        parent.addChild(pavement)
        return pavement
    }

    private static func makeEdgeLines(under parent: Entity) -> Entity {
        let group = Entity()
        group.name = "edgeLines"
        let innerEdge = TourTuning.trackRadius - TourTuning.trackHalfWidth
        let outerEdge = TourTuning.trackRadius + TourTuning.trackHalfWidth
        let width = TourTuning.edgeLineWidth
        let inner = ModelEntity(
            mesh: RingMesh.make(innerRadius: innerEdge, outerRadius: innerEdge + width),
            materials: [flatMaterial(lineColor)]
        )
        let outer = ModelEntity(
            mesh: RingMesh.make(innerRadius: outerEdge - width, outerRadius: outerEdge),
            materials: [flatMaterial(lineColor)]
        )
        group.addChild(inner)
        group.addChild(outer)
        group.position.y = lineY
        parent.addChild(group)
        return group
    }

    private static func makePosts(under parent: Entity) -> Entity {
        let group = Entity()
        group.name = "posts"
        let mesh = MeshResource.generateBox(size: SIMD3(0.15, TourTuning.postHeight, 0.15))
        let material = flatMaterial(postColor)
        let radii = [
            TourTuning.trackRadius - TourTuning.trackHalfWidth - TourTuning.postOffsetFromEdge,
            TourTuning.trackRadius + TourTuning.trackHalfWidth + TourTuning.postOffsetFromEdge
        ]
        for step in 0..<TourTuning.postCount {
            let angle = Float(step) / Float(TourTuning.postCount) * 2 * .pi
            for radius in radii {
                let post = ModelEntity(mesh: mesh, materials: [material])
                post.position = SIMD3(
                    radius * cos(angle),
                    TourTuning.postHeight / 2,
                    radius * sin(angle)
                )
                group.addChild(post)
            }
        }
        parent.addChild(group)
        return group
    }

    /// A stylized open-cockpit car from grouped boxes — a convertible, so the
    /// beat-1 POV camera (at y ≈ 1.05 inside the cockpit) looks out over the
    /// hood instead of into a roof. Everything except the seat back behind the
    /// camera stays below its sightline. Local frame matches the car rig:
    /// -z forward, +y up, origin at ground level.
    private static func makeCar(under parent: Entity) -> Entity {
        let group = Entity()
        group.name = "car"
        let bodyMaterial = flatMaterial(carBodyColor)
        let trimMaterial = flatMaterial(carCabinColor)

        let body = ModelEntity(
            mesh: .generateBox(size: SIMD3(1.9, 0.55, 4.4), cornerRadius: 0.12),
            materials: [bodyMaterial]
        )
        body.position = SIMD3(0, 0.45, 0)

        let hood = ModelEntity(
            mesh: .generateBox(size: SIMD3(1.7, 0.26, 1.1), cornerRadius: 0.1),
            materials: [bodyMaterial]
        )
        hood.position = SIMD3(0, 0.76, -1.0)

        let leftPod = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.2, 0.3, 2.0), cornerRadius: 0.08),
            materials: [bodyMaterial]
        )
        leftPod.position = SIMD3(-0.85, 0.78, 0.4)
        let rightPod = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.2, 0.3, 2.0), cornerRadius: 0.08),
            materials: [bodyMaterial]
        )
        rightPod.position = SIMD3(0.85, 0.78, 0.4)

        let seatBack = ModelEntity(
            mesh: .generateBox(size: SIMD3(1.2, 0.45, 0.3), cornerRadius: 0.1),
            materials: [trimMaterial]
        )
        seatBack.position = SIMD3(0, 0.9, 1.15)

        let spoiler = ModelEntity(
            mesh: .generateBox(size: SIMD3(1.7, 0.08, 0.5), cornerRadius: 0.03),
            materials: [trimMaterial]
        )
        spoiler.position = SIMD3(0, 1.0, 2.0)

        for part in [body, hood, leftPod, rightPod, seatBack, spoiler] {
            group.addChild(part)
        }
        group.addChild(makeHoodOrnamentFrame())
        parent.addChild(group)
        return group
    }

    /// The little Earth globe on the hood — its own entity (not part of `car`),
    /// so at the car→space seam the car and the brass frame can fade while this
    /// sphere stays put and the camera pushes into it, then a match cut swaps
    /// it for the real Earth at the same apparent size. Textured with the same
    /// stylized Earth map once it loads (a desktop globe has a map, after all).
    private static func makeOrnamentGlobe(under parent: Entity) -> Entity {
        let globe = ModelEntity(
            mesh: .generateSphere(radius: TourTuning.ornamentGlobeRadius),
            materials: [UnlitMaterial(color: UIColor(red: 0.09, green: 0.22, blue: 0.42, alpha: 1))]
        )
        globe.name = "ornamentGlobe"
        globe.position = TourTuning.ornamentGlobeCenter
        globe.orientation = simd_quatf(
            angle: TourTuning.earthAxialTiltDegrees * .pi / 180,
            axis: [0, 0, 1]
        )
        parent.addChild(globe)
        return globe
    }

    /// The ornament's post and tilted half-circle meridian frame that cradle
    /// the globe. Part of the `car` group so it fades out with the car during
    /// the morph, leaving the globe alone to become the Earth.
    private static func makeHoodOrnamentFrame() -> Entity {
        let group = Entity()
        group.name = "hoodOrnamentFrame"
        let frameMaterial = flatMaterial(UIColor(red: 0.83, green: 0.69, blue: 0.32, alpha: 1))
        let center = TourTuning.ornamentGlobeCenter
        let ringRadius = TourTuning.ornamentGlobeRadius * 1.37
        let hoodTopY: Float = 0.89

        // Post from the hood up to the cradle's lowest point.
        let cradleBottomY = center.y - ringRadius
        let postHeight = cradleBottomY - hoodTopY
        let post = ModelEntity(
            mesh: .generateBox(size: SIMD3(0.03, postHeight, 0.03)),
            materials: [frameMaterial]
        )
        post.position = SIMD3(center.x, hoodTopY + postHeight / 2, center.z)
        group.addChild(post)

        // Lower semicircle arc (π…2π) of short tangent bars, tilted to the
        // Earth's axial angle, cradling the globe from below and open at top.
        let assembly = Entity()
        assembly.position = center
        assembly.orientation = simd_quatf(
            angle: TourTuning.earthAxialTiltDegrees * .pi / 180,
            axis: [0, 0, 1]
        )
        let segments = 11
        let barLength = ringRadius * Float.pi / Float(segments - 1)
        for i in 0..<segments {
            let theta = Float.pi + Float.pi * Float(i) / Float(segments - 1)
            let bar = ModelEntity(
                mesh: .generateBox(size: SIMD3(0.02, barLength * 1.15, 0.02)),
                materials: [frameMaterial]
            )
            bar.position = SIMD3(ringRadius * cos(theta), ringRadius * sin(theta), 0)
            bar.orientation = simd_quatf(angle: theta, axis: [0, 0, 1])
            assembly.addChild(bar)
        }
        group.addChild(assembly)
        return group
    }
}

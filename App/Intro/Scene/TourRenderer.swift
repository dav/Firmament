import Combine
import RealityKit
import UIKit

/// Owns the tour's RealityKit view: a non-AR `ARView` with a scripted virtual
/// camera. Applying a `TourFrame` is stateless — rig transforms, camera pose,
/// and every action value are functions of the sampled time — so the DEBUG
/// scrubber can jump anywhere and the scene follows.
@MainActor
final class TourRenderer {
    let arView: ARView

    /// Scale-space parent of everything; the final beats' approach ramp
    /// animates its scale.
    let worldRig = Entity()
    private let trackRoot = Entity()
    private let spaceRoot = Entity()
    private let carRig = Entity()
    private let earthRig = Entity()
    private let cameraEntity = PerspectiveCamera()
    private var groups: [TourEntityID: Entity] = [:]
    private var spaceScene: SpaceSceneState?
    private var updateSubscription: (any Cancellable)?
    private var homeLatitudeDegrees: Double = 0
    private var homeLongitudeDegrees: Double = 0
    /// Last-applied values, so unchanged frames don't touch components — the
    /// apply loop runs at render rate and component sets aren't free.
    private var appliedOpacities: [TourEntityID: Float] = [:]
    private var appliedWorldScale: Float = 1

    init() {
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)

        let worldAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(worldAnchor)
        worldAnchor.addChild(worldRig)
        worldRig.addChild(trackRoot)
        worldRig.addChild(spaceRoot)
        trackRoot.addChild(carRig)
        spaceRoot.addChild(earthRig)

        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
        cameraEntity.camera.fieldOfViewOrientation = .vertical
        cameraEntity.camera.near = 0.05
        cameraEntity.camera.far = 5_000
    }

    /// Builds all tour entities, synchronously — nothing here may await, so
    /// the tour can never boot to a black screen waiting on assets. `home` is
    /// the device's coordinates, used for the stylized Earth's surface marker
    /// and the final beat's camera target.
    func buildScene(homeLatitudeDegrees: Double, homeLongitudeDegrees: Double) {
        self.homeLatitudeDegrees = homeLatitudeDegrees
        self.homeLongitudeDegrees = homeLongitudeDegrees
        groups = TrackSceneBuilder.build(trackRoot: trackRoot, carRig: carRig)
        let space = SpaceSceneBuilder.build(
            spaceRoot: spaceRoot,
            earthRig: earthRig,
            homeLatitudeDegrees: homeLatitudeDegrees,
            homeLongitudeDegrees: homeLongitudeDegrees
        )
        spaceScene = space
        groups.merge(space.groups) { current, _ in current }
        Log.info("intro.tour.built", ["groups": groups.count])
    }

    /// Loads the Earth texture off the boot path and swaps it into both the
    /// space Earth and the hood-ornament globe (so the little globe and the
    /// real Earth it morphs into wear the same map).
    func loadEarthTexture() async {
        guard let texture = try? await TextureResource(named: "earth-stylized") else {
            Log.warn("intro.earthTexture.missing")
            return
        }
        spaceScene?.applyEarthTexture(texture)
        if let globe = groups[.ornamentGlobe] as? ModelEntity {
            globe.model?.materials = [SpaceSceneState.earthMaterial(texture: texture)]
        }
    }

    /// Subscribes to the render loop: each frame advances the director's clock
    /// and applies its current sample. Applying even while paused keeps the
    /// scene live under scrubbing.
    func startTicking(director: TourDirector) {
        var tickCount = 0
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self, weak director] event in
            guard let self, let director else { return }
            tickCount += 1
            director.advance(by: event.deltaTime)
            if let frame = director.currentFrame {
                self.apply(frame)
            }
            if tickCount == 1 || tickCount == 120 {
                self.logTickDiagnostics(count: tickCount)
            }
        }
    }

    /// One-shot scene sanity snapshot (first tick and ~2 s in): where the
    /// camera and car actually are, so a black tour is diagnosable from logs.
    private func logTickDiagnostics(count: Int) {
        let cameraPosition = cameraEntity.position(relativeTo: nil)
        let carPosition = carRig.position(relativeTo: nil)
        let anchorStates = arView.scene.anchors.map { anchor in
            "\(anchor.name.isEmpty ? "anchor" : anchor.name):\(anchor.isAnchored ? "anchored" : "unanchored")"
        }
        Log.info("intro.tour.tick", [
            "n": count,
            "camera": "\(cameraPosition.x),\(cameraPosition.y),\(cameraPosition.z)",
            "camera_fov": cameraEntity.camera.fieldOfViewInDegrees,
            "camera_near": cameraEntity.camera.near,
            "camera_far": cameraEntity.camera.far,
            "car": "\(carPosition.x),\(carPosition.y),\(carPosition.z)",
            "car_enabled_in_hierarchy": groups[.car]?.isEnabledInHierarchy ?? false,
            "groups": groups.count,
            "anchors": anchorStates.joined(separator: ",")
        ])
    }

    func stopTicking() {
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    // MARK: - Frame application

    func apply(_ frame: TourFrame) {
        carRig.setTransformMatrix(TourMath.carTransform(at: frame.time), relativeTo: trackRoot)
        earthRig.setTransformMatrix(TourMath.earthTransform(at: frame.time), relativeTo: spaceRoot)
        spaceScene?.setEarthSpin(time: frame.time)
        applyActions(frame)
        applyCamera(frame)
    }

    private func applyActions(_ frame: TourFrame) {
        // Start every fade target at its scene default so a sample fully
        // determines visibility — the pure-function-of-time contract.
        var opacities: [TourEntityID: Float] = [:]
        for target in TourEntityID.allCases {
            opacities[target] = Self.defaultOpacity(of: target)
        }
        var worldScale: Float = 1

        for value in frame.actionValues {
            apply(value, opacities: &opacities, worldScale: &worldScale)
        }

        for (target, opacity) in opacities where appliedOpacities[target] != opacity {
            guard let entity = groups[target] else { continue }
            Self.applyOpacity(opacity, to: entity)
            appliedOpacities[target] = opacity
        }
        if worldScale != appliedWorldScale {
            worldRig.scale = SIMD3(repeating: worldScale)
            appliedWorldScale = worldScale
        }
    }

    /// Fully opaque entities carry no `OpacityComponent` at all and fully
    /// transparent ones are disabled outright — the component is only used
    /// mid-fade. Some renderers (notably the simulator's) skip drawing
    /// subtrees that carry the component, so it must never sit on an entity
    /// that should read as plainly visible.
    static func applyOpacity(_ opacity: Float, to entity: Entity) {
        let clamped = min(max(opacity, 0), 1)
        entity.isEnabled = clamped > 0.001
        if clamped >= 0.999 {
            entity.components.remove(OpacityComponent.self)
        } else if entity.isEnabled {
            entity.components.set(OpacityComponent(opacity: clamped))
        }
    }

    private func apply(
        _ value: ResolvedActionValue,
        opacities: inout [TourEntityID: Float],
        worldScale: inout Float
    ) {
        switch value.effect {
        case .fadeOpacity(let from, let to):
            guard value.progress > 0 else { return }
            opacities[value.target] = from + (to - from) * Float(value.progress)
        case .drawOrbit:
            spaceScene?.setOrbitDrawFraction(value.progress)
        case .unfoldGrid:
            spaceScene?.setGridUnfoldFraction(value.progress)
        case .revealNodes:
            spaceScene?.setNodeRevealFraction(value.progress)
        case .rampScale(let from, let to):
            guard value.progress > 0 else { return }
            worldScale = from * pow(to / from, Float(value.progress))
        }
    }

    /// Track scenery and the car start visible. Earth, sun, and the home
    /// marker start invisible until their fade actions run; the orbit, grid,
    /// and node groups stay at full opacity because their draw/unfold/reveal
    /// effects control what exists inside them.
    private static func defaultOpacity(of target: TourEntityID) -> Float {
        switch target {
        case .grass, .posts, .trackEdgeLines, .trackPavement, .car, .worldRig,
             .orbitPath, .spaceGrid, .gridNodes, .ornamentGlobe:
            return 1
        case .earth, .sun, .homeMarker:
            return 0
        }
    }

    // MARK: - Camera

    /// A resolved world-space camera pose plus the point it looks at, which
    /// sizes the near/far planes.
    private struct ResolvedPose {
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let lookTarget: SIMD3<Float>
    }

    private func applyCamera(_ frame: TourFrame) {
        let pose = scriptedCameraPose(of: frame)
        cameraEntity.setPosition(pose.position, relativeTo: nil)
        cameraEntity.setOrientation(pose.rotation, relativeTo: nil)
        cameraEntity.camera.fieldOfViewInDegrees = frame.camera.fovDegrees
        applyClipPlanes(position: pose.position, focus: pose.lookTarget)
    }

    /// Brackets the depth range to the actual scene each frame instead of a
    /// fixed 0.05…5000 (ratio 100k, which collapses depth precision the moment
    /// the camera dives into the node cloud and reads as flickering "jitter").
    /// The near plane — which dominates precision — is pushed out in proportion
    /// to how far the camera is from what it's looking at, while `far` stays
    /// generous enough never to clip the big grass disc or the distant sun.
    private func applyClipPlanes(position: SIMD3<Float>, focus: SIMD3<Float>) {
        let focusDistance = simd_distance(position, focus)
        let near = min(max(focusDistance * 0.02, 0.03), 2)
        let far = max(focusDistance * 4, 600)
        cameraEntity.camera.near = near
        cameraEntity.camera.far = far
    }

    /// The world pose the tour script puts the camera at for `frame`'s time,
    /// plus the world-space point it is looking at (used to size the near/far
    /// planes).
    private func scriptedCameraPose(of frame: TourFrame) -> ResolvedPose {
        let fromPose = worldPose(of: frame.camera.from, frame: frame)
        let toPose = worldPose(of: frame.camera.to, frame: frame)
        let blend = Float(frame.camera.blend)
        return ResolvedPose(
            position: TourMath.mix(fromPose.position, toPose.position, blend),
            rotation: simd_slerp(fromPose.rotation, toPose.rotation, blend),
            lookTarget: TourMath.mix(fromPose.lookTarget, toPose.lookTarget, blend)
        )
    }

    private func worldPose(of keyframe: CameraKeyframe, frame: TourFrame) -> ResolvedPose {
        let frameMatrix = referenceMatrix(for: keyframe.frame, frame: frame)
        let position = TourMath.transform(frameMatrix, keyframe.position)
        let lookTarget = TourMath.transform(frameMatrix, keyframe.lookAt)
        let up = simd_normalize(TourMath.rotate(frameMatrix, [0, 1, 0]))
        // North tangent keeps the roll stable when the camera looks straight
        // up the frame's own zenith (the tour's final pose).
        let north = simd_normalize(TourMath.rotate(frameMatrix, [0, 0, -1]))
        let rotation = TourMath.lookRotation(
            forward: lookTarget - position,
            up: up,
            fallbackUp: north
        )
        return ResolvedPose(position: position, rotation: rotation, lookTarget: lookTarget)
    }

    private func referenceMatrix(for ref: CameraFrameRef, frame: TourFrame) -> simd_float4x4 {
        switch ref {
        case .world:
            return worldRig.transformMatrix(relativeTo: nil)
        case .car:
            return worldRig.transformMatrix(relativeTo: nil) * TourMath.carTransform(at: frame.time)
        case .earth:
            return spaceMatrix(at: frame.time)
        case .earthAtBeatStart:
            return spaceMatrix(at: frame.beatStartTime)
        case .home:
            let earthMatrix = spaceMatrix(at: frame.time)
            return TourMath.homeTransform(
                earthMatrix: earthMatrix,
                latitudeDegrees: homeLatitudeDegrees,
                longitudeDegrees: homeLongitudeDegrees,
                earthRadius: TourTuning.earthRadius
            )
        }
    }

    private func spaceMatrix(at time: Double) -> simd_float4x4 {
        worldRig.transformMatrix(relativeTo: nil) * TourMath.earthTransform(at: time)
    }
}

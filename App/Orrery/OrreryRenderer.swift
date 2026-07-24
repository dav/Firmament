import Combine
import RealityKit
import UIKit

/// Tuning for the picture-in-picture orrery. Scene scale, orbit period, spin,
/// and tilt all come from `TourTuning` so the PiP matches the intro tour;
/// only the camera framing and the tube/ride ring shapes live here.
nonisolated enum OrreryTuning {
    /// Camera pose in the Earth-tracking frame (-z toward the sun, +y ecliptic
    /// north — the same frame as the tour's final beats): above and behind the
    /// Earth, looking past it so a few grid cells of streaming nodes fit in
    /// the small window.
    static let cameraPosition = SIMD3<Float>(0, 14, 22)
    static let cameraLookAt = SIMD3<Float>(0, 0, -12)
    static let cameraFovDegrees: Float = 55
    static let cameraNear: Float = 1
    static let cameraFar: Float = 500
    /// Tube mode: Earth floats well inside the bore, like the real layout.
    static let tubeRingRadius: Float = 4
    static let tubeNodesPerRing = 8
    static let tubeCubeEdge: Float = 0.55
    /// Ride mode: the tube hugs the Earth (it threads through the observer at
    /// real scale, indistinguishable from Earth's path from this far out).
    static let rideRingRadius: Float = 1.5
    static let rideNodesPerRing = 8
    static let rideCubeEdge: Float = 0.3

    // Visibility windows, in orbit stations (one station = one grid spacing
    // of arc, ~4.8°). Only geometry near Earth renders — the far side of the
    // orbit stays empty, matching the live view and keeping the PiP cheap.
    /// Stations along the orbit: one per grid spacing of arc (75).
    static let orbitStationCount = Int((2 * Float.pi * TourTuning.orbitRadius / TourTuning.gridSpacing).rounded())
    /// Grid mode: sectors of lattice cubes shown around Earth (±8 ≈ ±38°).
    static let gridSectorHalfSpan = 8
    /// Tube/ride: cube rings shown around Earth (the "node window").
    static let tubeCubeRingHalfSpan = 2
    /// Tube only: white outline hoops continue the bore this far (±12 ≈ ±57°),
    /// like the live view's distant ring sketches.
    static let tubeOutlineHalfSpan = 12
    /// Line segments per outline hoop.
    static let outlinePointsPerHoop = 24
}

/// Owns the PiP orrery's RealityKit view: a non-AR `ARView` with a virtual
/// camera that tracks a miniature Earth around its orbit, streaming through
/// whichever node layout the live sky is currently showing. Time runs on the
/// render clock while expanded and pauses (`stop()`) while collapsed.
@MainActor
final class OrreryRenderer {
    let arView: ARView

    private let spaceRoot = Entity()
    private let earthRig = Entity()
    private let earthSpin = Entity()
    private let earthEntity: ModelEntity
    private let cameraEntity = PerspectiveCamera()
    private var nodeGroups: [RenderMode: OrreryNodeGroup] = [:]
    private var activeMode: RenderMode
    private var updateSubscription: (any Cancellable)?
    private var time: Double = 0

    init(mode: RenderMode, homeLatitudeDegrees: Double?, homeLongitudeDegrees: Double?) {
        activeMode = mode
        arView = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        arView.environment.background = .color(.black)

        let worldAnchor = AnchorEntity(world: .zero)
        arView.scene.addAnchor(worldAnchor)
        worldAnchor.addChild(spaceRoot)
        spaceRoot.addChild(earthRig)
        earthRig.addChild(earthSpin)

        let cameraAnchor = AnchorEntity(world: .zero)
        cameraAnchor.addChild(cameraEntity)
        arView.scene.addAnchor(cameraAnchor)
        cameraEntity.camera.fieldOfViewOrientation = .vertical
        cameraEntity.camera.fieldOfViewInDegrees = OrreryTuning.cameraFovDegrees
        cameraEntity.camera.near = OrreryTuning.cameraNear
        cameraEntity.camera.far = OrreryTuning.cameraFar

        earthEntity = OrrerySceneBuilder.buildStatics(
            spaceRoot: spaceRoot,
            earthSpin: earthSpin,
            homeLatitudeDegrees: homeLatitudeDegrees,
            homeLongitudeDegrees: homeLongitudeDegrees
        )
        setMode(mode)
        applyPoses()
        Task { await loadEarthTexture() }
    }

    /// Shows the node group for `mode`, building it on first use. Groups for
    /// other modes stay cached but disabled, so toggling the pill is instant
    /// after the first visit.
    func setMode(_ mode: RenderMode) {
        activeMode = mode
        if nodeGroups[mode] == nil {
            nodeGroups[mode] = OrrerySceneBuilder.makeNodes(for: mode, under: spaceRoot)
        }
        for (groupMode, group) in nodeGroups {
            group.root.isEnabled = groupMode == mode
        }
        nodeGroups[mode]?.update(station: currentStation())
    }

    /// Subscribes to the render loop; each frame advances the orrery clock and
    /// re-poses the Earth, its spin, and the tracking camera.
    func start() {
        guard updateSubscription == nil else { return }
        updateSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
            guard let self else { return }
            self.time += event.deltaTime
            self.applyPoses()
        }
    }

    func stop() {
        updateSubscription?.cancel()
        updateSubscription = nil
    }

    private func applyPoses() {
        earthRig.setTransformMatrix(TourMath.earthTransform(at: time), relativeTo: spaceRoot)
        earthSpin.orientation = TourMath.earthSpinOrientation(at: time)
        // Slide the node visibility window along with Earth (early-outs
        // inside until the station index changes).
        nodeGroups[activeMode]?.update(station: currentStation())

        let earthMatrix = earthRig.transformMatrix(relativeTo: nil)
        let position = TourMath.transform(earthMatrix, OrreryTuning.cameraPosition)
        let lookTarget = TourMath.transform(earthMatrix, OrreryTuning.cameraLookAt)
        cameraEntity.setPosition(position, relativeTo: nil)
        cameraEntity.setOrientation(
            TourMath.lookRotation(forward: lookTarget - position, up: [0, 1, 0]),
            relativeTo: nil
        )
    }

    /// Earth's nearest orbit station at the orrery's current time.
    private func currentStation() -> Int {
        let count = OrreryTuning.orbitStationCount
        let index = Int((TourMath.earthAngle(at: time) / OrrerySceneBuilder.stationAngle).rounded())
        return ((index % count) + count) % count
    }

    /// Same texture-load-off-the-boot-path pattern as the tour: the orrery
    /// appears immediately with a flat ocean-blue Earth and the map swaps in
    /// when ready.
    private func loadEarthTexture() async {
        guard let texture = try? await TextureResource(named: "earth-stylized") else {
            Log.warn("orrery.earthTexture.missing")
            return
        }
        earthEntity.model?.materials = [SpaceSceneState.earthMaterial(texture: texture)]
    }
}

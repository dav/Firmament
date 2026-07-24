import ARKit
import FirmamentCore
import RealityKit
import SwiftUI

/// How a single node cube should look this tick.
nonisolated struct NodeStyle: Hashable, Sendable {
    var isGhost: Bool
    var isOnEclipticPlane: Bool
    var brightnessLevel: Int
}

/// A node's placement this tick and where it is headed by the next tick. Produced
/// off the main actor; applied to a RealityKit entity on it.
nonisolated struct NodePlacement: Sendable {
    let node: LatticeNode
    let nowPosition: SIMD3<Float>
    let nowScale: Float
    let targetPosition: SIMD3<Float>
    let targetScale: Float
    let style: NodeStyle
}

/// The nearest/farthest distance span of a visible set, used to map true distance
/// onto a dome radius.
nonisolated struct DistanceRange: Sendable {
    let minKm: Double
    let spanKm: Double
}

/// The scale numbers behind one frame, for the on-screen HUD: the cube edge
/// actually rendered (after the never-touch cap) and the true node gaps.
nonisolated struct ScaleInfo: Sendable {
    let cubeEdgeKm: Double
    let betweenCubesKm: Double
    let betweenRingsKm: Double
    /// Gap between the distant snapped outline rings; nil when none render.
    let farRingGapKm: Double?
}

/// A per-tick telemetry snapshot for the throttled render summary.
nonisolated struct RenderStats: Sendable {
    var aboveHorizonCount: Int
    var placedCount: Int
    var nearestKm: Double
    var farthestKm: Double
    var sunAzimuthDegrees: Double
    var sunElevationDegrees: Double
    var sunAboveHorizon: Bool
    var didCapNodes: Bool
    /// Tube mode: whether any exact-spacing ring (the ±20-ring node window) is
    /// above the horizon — when false, every visible ring is a distant snapped
    /// station and the HUD flags the ring spacing as currently hidden.
    var isNearRingWindowVisible: Bool
}

/// A fully computed frame: everything needed to update the scene, derived purely
/// from observer state and configuration. Built off the main actor so the 2 Hz
/// astronomy math never stalls the render loop; applied on the main actor.
nonisolated struct SkyFrame: Sendable {
    let placements: [NodePlacement]
    let standardLineData: LineMeshData?
    /// Rotation aligning every cube with the lattice's ecliptic axes.
    let latticeOrientation: simd_quatf
    let sunPosition: SIMD3<Float>
    let sunScale: Float
    let stats: RenderStats
}

/// Owns the live ARView and its session; the dome itself lives in a
/// `SkyDomeScene` so the intro tour can render an identical dome in its own
/// scene during the tour-to-AR meld. Astronomy updates arrive at a slow
/// cadence; per-frame device attitude is ARKit's job, not ours.
///
/// Each node's dome radius grows monotonically with its true distance, so the
/// depth buffer occludes far cubes behind near ones, while cube scale preserves
/// true angular size at every radius. Frame computation (`computeFrame`) is pure
/// and runs off the main actor; only `render(_:)` touches RealityKit.
@MainActor
final class SkyRenderer {
    let arView: ARView

    nonisolated static let minDomeRadiusMeters = 150.0
    nonisolated static let maxDomeRadiusMeters = 600.0
    /// Grid mode fills to this budget (the lattice shrinks its reach to fit).
    /// Kept modest: the live dome is hidden through the whole intro, so the
    /// first tick after the handoff builds every grid entity at once — a big
    /// count there is a visible hitch just as the app appears. Fewer, nearer
    /// nodes read better and keep each 4 Hz tick's entity work cheap.
    nonisolated static let maxRenderedNodes = 800
    /// Tube and ride modes render a fixed window of rings ahead of and behind
    /// Earth, so the visible tube length depends only on ring spacing — never on
    /// the ring node count. 41 rings × 50 nodes worst case stays near the budget.
    nonisolated static let tubeRingHalfSpan = 20
    /// Tube mode sketches outline hoops (no cube entities) at doubling gaps out
    /// to this distance beyond the node window, so the bore is visible from
    /// anywhere on the globe even when tight spacing makes the window short.
    nonisolated static let farTubeHalfLengthKm = 100_000.0
    static let ghostOpacity: Float = 0.35
    /// Cubes never exceed this fraction of the node spacing, so neighbors can't touch.
    nonisolated static let maxEdgeFractionOfSpacing = 0.3
    nonisolated static let sunRadiusKm = 696_340.0
    /// The sun marker renders larger than life so it reads as a landmark.
    nonisolated static let sunSizeBoost = 4.0
    /// Sunward nodes render brighter than anti-sunward ones, as an orientation cue.
    nonisolated static let brightnessLevels = 5
    static let minBrightness = 0.45

    /// Astronomy tick cadence; entities animate between ticks, so motion stays
    /// smooth at display refresh rate while math runs off-main. A shorter interval
    /// means smaller linear-prediction error per segment (less velocity "kink" at
    /// each tick boundary), which reads as smoother motion when the sky sweeps fast.
    static let updateInterval: TimeInterval = 0.25

    /// The feed occluder sits beyond the dome (max 600 m) but inside the far
    /// plane, so it blacks out the camera feed without hiding any nodes.
    static let feedOccluderRadius: Float = 800

    let domeScene = SkyDomeScene()
    /// True while camera tracking is `.normal`; the intro meld gates on this.
    private(set) var isTrackingNormal = false
    private var feedOccluder: ModelEntity?
    private var occluderAnchor: AnchorEntity?
    private var isRevealingFeed = false
    private var consecutiveSessionFailures = 0
    // Retained here because ARSession holds its delegate weakly. A dedicated object
    // (rather than SkyRenderer itself) keeps us from ever implementing the per-frame
    // `session(_:didUpdate:)` callback that would flood the log at display rate.
    private let sessionObserver = ARSessionObserver()

    init() {
        arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        domeScene.attach(to: arView.scene)
        sessionObserver.onSessionFailed = { [weak self] in self?.restartSession() }
        sessionObserver.onTrackingStateChanged = { [weak self] isNormal in
            self?.isTrackingNormal = isNormal
            if isNormal { self?.consecutiveSessionFailures = 0 }
        }
    }

    func startSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            // Simulator: the intro tour still runs; there's just no live AR.
            Log.warn("ar.session.unsupported")
            return
        }
        arView.session.delegate = sessionObserver
        arView.session.run(makeConfiguration())
        Log.info("ar.session.start", ["worldAlignment": "gravityAndHeading"])
    }

    /// Recover from a failed session ("Required sensor failed." is a common,
    /// usually-transient first-launch failure). Bounded so a truly dead sensor
    /// can't spin in a restart loop; the counter resets once tracking is normal.
    func restartSession() {
        consecutiveSessionFailures += 1
        guard consecutiveSessionFailures <= 3 else {
            Log.error("ar.session.restartGaveUp", ["failures": consecutiveSessionFailures])
            return
        }
        Log.info("ar.session.restart", ["attempt": consecutiveSessionFailures])
        arView.session.run(makeConfiguration(), options: [.resetTracking, .removeExistingAnchors])
    }

    private func makeConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        configuration.planeDetection = []
        return configuration
    }

    /// Applies a precomputed frame to the live dome.
    func render(_ frame: SkyFrame, faceColors: [Color.Resolved], animationDuration: TimeInterval) {
        domeScene.apply(
            frame,
            faceColors: faceColors,
            cameraTranslation: arView.cameraTransform.translation,
            animationDuration: animationDuration
        )
    }

    // MARK: - Feed occluder (intro meld)

    /// Blacks out the camera feed with an in-scene sphere while the intro tour
    /// plays. Lives under its own anchor — not the dome's — so the dome can be
    /// hidden independently while the occluder keeps the feed dark. At 800 m
    /// radius, the camera never meaningfully leaves its center.
    func installFeedOccluder() {
        guard feedOccluder == nil else { return }
        var material = UnlitMaterial(color: .black)
        material.faceCulling = .none
        let occluder = ModelEntity(
            mesh: .generateSphere(radius: Self.feedOccluderRadius),
            materials: [material]
        )
        occluder.name = "feedOccluder"
        let anchor = AnchorEntity(world: .zero)
        anchor.addChild(occluder)
        arView.scene.addAnchor(anchor)
        occluderAnchor = anchor
        feedOccluder = occluder
    }

    /// Hides or shows the node dome wholesale. Hidden during the intro so the
    /// screen past the tour is pure black until the reveal fades the
    /// calculated nodes in at their true positions.
    func setDomeHidden(_ hidden: Bool) {
        domeScene.skyAnchor.isEnabled = !hidden
    }

    /// Fades the dome in (wall-clock driven). If the renderer ignores
    /// `OpacityComponent`, this degrades to the nodes appearing when the
    /// component is removed at the end.
    func revealDome(duration: TimeInterval) {
        let anchor = domeScene.skyAnchor
        guard !anchor.isEnabled else { return }
        anchor.components.set(OpacityComponent(opacity: 0))
        anchor.isEnabled = true
        let start = Date.now
        Task {
            while true {
                let elapsed = Date.now.timeIntervalSince(start)
                guard elapsed < duration else { break }
                anchor.components.set(OpacityComponent(opacity: Float(elapsed / duration)))
                try? await Task.sleep(for: .milliseconds(33))
            }
            anchor.components.remove(OpacityComponent.self)
            Log.info("intro.domeReveal.done")
        }
    }

    /// Fades the occluder out so the camera feed blooms in behind the nodes,
    /// then removes it. The nodes and sun render in front and stay at full
    /// brightness throughout. Driven by stepping the material's transparent
    /// blending per frame — deterministic, and the same mechanism the node
    /// ghost materials already use — with a guaranteed removal at the end.
    func revealFeed(duration: TimeInterval) {
        guard let occluder = feedOccluder, !isRevealingFeed else { return }
        isRevealingFeed = true
        Log.info("intro.reveal.begin", ["duration_s": duration])
        // Wall-clock driven: opacity comes from elapsed time, not a step
        // counter, so the fade completes on schedule even when a congested
        // main actor delivers far fewer iterations than requested.
        let start = Date.now
        Task { [weak self] in
            while true {
                let elapsed = Date.now.timeIntervalSince(start)
                guard elapsed < duration, self?.feedOccluder != nil else { break }
                var material = UnlitMaterial(color: .black)
                material.faceCulling = .none
                let opacity = Float(1 - elapsed / duration)
                material.blending = .transparent(opacity: .init(floatLiteral: opacity))
                occluder.model?.materials = [material]
                try? await Task.sleep(for: .milliseconds(33))
            }
            occluder.removeFromParent()
            self?.occluderAnchor?.removeFromParent()
            self?.occluderAnchor = nil
            self?.feedOccluder = nil
            self?.isRevealingFeed = false
            Log.info("intro.reveal.done", ["actual_s": Date.now.timeIntervalSince(start)])
        }
    }

    /// Safety net: force-removes the occluder no matter what state the reveal
    /// is in. Called when the intro reaches the live phase.
    func removeFeedOccluder() {
        guard feedOccluder != nil else { return }
        Log.info("intro.occluder.forceRemoved")
        feedOccluder?.removeFromParent()
        occluderAnchor?.removeFromParent()
        occluderAnchor = nil
        feedOccluder = nil
        isRevealingFeed = false
    }
}

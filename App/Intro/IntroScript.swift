import Foundation
import simd

// =============================================================================
// THE intro tour tweak file.
//
// Everything about the tour's choreography lives here: beat order, captions,
// timing rules, camera keyframes, scene actions, and the tuning constants the
// scene builders read. Nothing else in the app hard-codes beat content — to
// change a camera move, a fade window, or a duration, edit this file only.
// In DEBUG builds the on-screen scrubber (wrench button during the tour) lets
// you pause, seek, and replay any beat while iterating on these values.
//
// Narration audio: record one segment per beat and drop it into
// Resources/Intro/Audio/ named `intro-NN-slug.m4a`:
//   intro-01-racecar.m4a          intro-02-no-surroundings.m4a
//   intro-03-lines-vanish.m4a     intro-04-blackness.m4a
//   intro-05-earth-reveal.m4a     intro-06-orbit-drawn.m4a
//   intro-07-grid-unfolds.m4a     intro-08-nodes-appear.m4a
//   intro-09-zoom-home.m4a
// A beat lasts max(recording + audioPaddingAfter, minDuration); beats with no
// recording use placeholderDuration. Camera keyframes and action ranges are
// fractions of beat progress, so they stretch with your narration.
//
// Camera frames (see CameraFrameRef): `car` follows the race car (-z forward),
// `earth` tracks the Earth (-z toward the sun), `earthAtBeatStart` freezes the
// earth frame where the beat began (Earth sails on past), `home` sits at the
// device's location on the stylized Earth (+y zenith). A beat may start its
// keyframes in one frame and end in another; the camera blends between the
// resolved world poses, which is how each handoff stays cut-free.
// =============================================================================

/// Scene-scale tuning for the tour's two stylized spaces. Track space is
/// roughly 1 unit ≈ 1 m; heliocentric space compresses wildly on purpose
/// (Earth radius 1 unit, orbit radius 60) so the story reads.
nonisolated enum TourTuning {
    // Track (beats 1–4)
    static let trackRadius: Float = 40
    static let trackHalfWidth: Float = 5
    static let edgeLineWidth: Float = 0.35
    static let grassRadius: Float = 220
    static let postCount = 48
    static let postHeight: Float = 1.6
    static let postOffsetFromEdge: Float = 1.8
    /// Seconds per car lap. 48 posts / 34 s ≈ one post every 0.7 s in POV.
    static let carLapDuration: Double = 34

    // Heliocentric space (beats 5–9); sun at the world origin.
    static let orbitRadius: Float = 60
    static let earthRadius: Float = 1
    static let sunRadius: Float = 4
    /// Seconds per full stylized orbit — wildly exaggerated so motion reads:
    /// ≈2.5 units/s along the orbit, one grid cell every ~2 s.
    static let earthOrbitPeriod: Double = 150
    /// Earth's orbit angle at tour time 0, radians.
    static let earthStartAngle: Float = 0
    /// Spacing of the space grid and of the stylized lattice nodes.
    static let gridSpacing: Float = 5
    /// Orbit path segments; the draw-on effect reveals them in order.
    static let orbitSegmentCount = 256
    /// Radial bands the grid unfolds in, sun → orbit.
    static let gridUnfoldBands = 24
    /// Where the orbit draw-on starts, roughly the Earth's position during the
    /// orbitDrawn beat so the path appears to extend from under the Earth.
    static let orbitDrawStartAngleDegrees: Float = 96
    /// Node reveal sweeps outward from this orbit angle, roughly the Earth's
    /// position during the nodesAppear beat.
    static let nodeRevealCenterAngleDegrees: Float = 149
    /// Stylized node cube edge as a fraction of grid spacing — exaggerated vs.
    /// the real app ratio so the cubes read from orbit distance.
    static let nodeCubeEdgeFraction: Float = 0.18
    // Hood ornament globe (also the morph target at the car→space seam). Its
    // position is in the car's local frame (-z forward, +y up); the tour's
    // final track-beat camera pushes into it until it fills the frame, then a
    // match cut swaps to the real Earth at the same apparent size.
    static let ornamentGlobeCenter = SIMD3<Float>(0, 1.22, -1.5)
    static let ornamentGlobeRadius: Float = 0.095

    /// Spin the textured Earth so its prime meridian lines up with the home
    /// marker's longitude convention; tune on device against a known location.
    /// (Starting estimate: with offset 0 the San Francisco marker landed over
    /// Eastern Europe, ~152° east, so the texture is wound back that far.)
    static let earthTextureLongitudeOffsetDegrees: Float = -152
    /// Earth's axial tilt, applied to the stylized globe's spin axis.
    static let earthAxialTiltDegrees: Float = 23.5
    /// Seconds per full Earth spin — wildly fast vs. reality, but a globe that
    /// visibly turns reads as alive during the orbit fly-through.
    static let earthSpinSecondsPerRevolution: Double = 4

    // Handoff: after the tour fades out, the app waits for the camera to
    // point at the sky, then fades the calculated nodes in and drops the
    // feed occluder.
    /// Camera-feed fade-in once the user is pointing at the sky.
    static let meldRevealSeconds: TimeInterval = 1.4
    /// Calculated-node fade-in, running alongside the feed reveal.
    static let domeFadeInSeconds: TimeInterval = 1.0
    /// Pointing-at-sky hysteresis: a bit above the horizon is enough. The
    /// reveal arms above the enter elevation and re-arms below the exit one.
    static let skyEnterElevationDegrees: Float = 10
    static let skyExitElevationDegrees: Float = 2
    /// The camera must hold above the enter elevation this long.
    static let skyDwellSeconds: TimeInterval = 0.4
    /// If pointing up but no nodes are above the horizon (pathological
    /// config), reveal anyway after this long — never trap the user.
    static let skyNoNodesTimeoutSeconds: TimeInterval = 3
}

// The declarative tour script: nine narrated beats. The whole point of this
// file is that every knob lives in one place.
nonisolated enum IntroScript {
    /// In-car POV pose shared by the end of beat 1 and the holds in beats 2–4.
    private static let povPosition = SIMD3<Float>(0, 1.05, 0.2)
    private static let povLookAt = SIMD3<Float>(0, 0.85, -10)
    private static let povFov: Float = 70

    private static func povKeyframe(progress: Double) -> CameraKeyframe {
        CameraKeyframe(progress: progress, frame: .car, position: povPosition, lookAt: povLookAt, fovDegrees: povFov)
    }

    static let script = TourScript(beats: [
        racecar, noSurroundings, linesVanish, blackness, earthReveal,
        orbitDrawn, gridUnfolds, nodesAppear, zoomHome
    ])

    private static let racecar =
        TourBeat(
            id: .racecar,
            caption: "Imagine you're in a race car, going around a circular track at night.",
            minDuration: 8,
            placeholderDuration: 10,
            camera: [
                CameraKeyframe(
                    progress: 0,
                    frame: .car,
                    position: SIMD3(0, 16, 22),
                    lookAt: SIMD3(0, 0, -8),
                    fovDegrees: 55
                ),
                CameraKeyframe(
                    progress: 0.4,
                    frame: .car,
                    position: SIMD3(0, 7, 11),
                    lookAt: SIMD3(0, 0.6, -9),
                    fovDegrees: 62
                ),
                CameraKeyframe(
                    progress: 1,
                    frame: .car,
                    position: povPosition,
                    lookAt: povLookAt,
                    fovDegrees: povFov
                )
            ]
        )

    private static let noSurroundings =
        TourBeat(
            id: .noSurroundings,
            caption: "But what if you couldn't see your surroundings?",
            minDuration: 6,
            placeholderDuration: 8,
            camera: [
                CameraKeyframe(
                    progress: 0,
                    frame: .car,
                    position: povPosition,
                    lookAt: povLookAt,
                    fovDegrees: povFov
                )
            ],
            actions: [
                SceneAction(target: .grass, effect: .fadeOpacity(from: 1, to: 0), range: 0.1...0.5),
                SceneAction(target: .posts, effect: .fadeOpacity(from: 1, to: 0), range: 0.5...0.9)
            ]
        )

    private static let linesVanish =
        TourBeat(
            id: .linesVanish,
            caption: "Or even the track itself?",
            minDuration: 4,
            placeholderDuration: 5,
            camera: [
                CameraKeyframe(
                    progress: 0,
                    frame: .car,
                    position: povPosition,
                    lookAt: povLookAt,
                    fovDegrees: povFov
                )
            ],
            actions: [
                SceneAction(target: .trackEdgeLines, effect: .fadeOpacity(from: 1, to: 0), range: 0.2...0.8),
                SceneAction(target: .trackPavement, effect: .fadeOpacity(from: 1, to: 0), range: 0.6...0.95)
            ]
        )

    private static let blackness =
        TourBeat(
            id: .blackness,
            caption: "Without any static reference points passing by, "
                + "it's hard to understand that you're moving at all.",
            minDuration: 6,
            placeholderDuration: 8,
            camera: [
                povKeyframe(progress: 0),
                povKeyframe(progress: 0.55),
                // Notice the little globe on the hood…
                CameraKeyframe(
                    progress: 0.75,
                    frame: .car,
                    position: SIMD3(0, 1.05, 0.1),
                    lookAt: TourTuning.ornamentGlobeCenter,
                    fovDegrees: 60
                ),
                // …and push into it until it fills the frame, ready to become
                // the real Earth in a match cut at the next beat's start.
                CameraKeyframe(
                    progress: 1,
                    frame: .car,
                    position: SIMD3(0, 1.206, -1.36),
                    lookAt: TourTuning.ornamentGlobeCenter,
                    fovDegrees: 50
                )
            ],
            actions: [
                SceneAction(target: .car, effect: .fadeOpacity(from: 1, to: 0), range: 0.6...0.85),
                // Bring the real Earth to full opacity behind the full-frame
                // globe, so the match cut lands on a solid Earth, not black.
                SceneAction(target: .earth, effect: .fadeOpacity(from: 0, to: 1), range: 0.9...1.0)
            ]
        )

    private static let earthReveal =
        TourBeat(
            id: .earthReveal,
            caption: "The Earth is doing this right now, zooming along its orbital track "
                + "around the Sun at roughly 107,000 kilometers per hour.",
            minDuration: 8,
            placeholderDuration: 9,
            camera: [
                // Match cut: opens on the Earth at the same apparent size the
                // ornament globe filled at the end of the previous beat (fov 50,
                // ~43° radius), then pulls back to reveal it whole and the Sun.
                CameraKeyframe(
                    progress: 0,
                    frame: .earth,
                    position: SIMD3(0, 0, 1.475),
                    lookAt: SIMD3(0, 0, 0),
                    fovDegrees: 50
                ),
                CameraKeyframe(
                    progress: 0.35,
                    frame: .earth,
                    position: SIMD3(0, 0.6, 3),
                    lookAt: SIMD3(0, 0, 0),
                    fovDegrees: 60
                ),
                CameraKeyframe(
                    progress: 1,
                    frame: .earth,
                    position: SIMD3(0, 3, 14),
                    lookAt: SIMD3(0, 0, -8),
                    fovDegrees: 60
                )
            ],
            actions: [
                // The stand-in globe is spent — retire it (already occluded by
                // the real Earth after the cut). Earth is already opaque, having
                // come up behind the globe during the previous beat.
                SceneAction(target: .ornamentGlobe, effect: .fadeOpacity(from: 1, to: 0), range: 0.0...0.08),
                SceneAction(target: .sun, effect: .fadeOpacity(from: 0, to: 1), range: 0.2...0.4)
            ]
        )

    private static let orbitDrawn =
        TourBeat(
            id: .orbitDrawn,
            caption: "But we don't feel like we're moving at all.",
            minDuration: 7,
            placeholderDuration: 9,
            camera: [
                CameraKeyframe(
                    progress: 0,
                    frame: .earth,
                    position: SIMD3(0, 3, 14),
                    lookAt: SIMD3(0, 0, -8),
                    fovDegrees: 60
                ),
                CameraKeyframe(
                    progress: 1,
                    frame: .earth,
                    position: SIMD3(0, 30, 45),
                    lookAt: SIMD3(0, 0, -25),
                    fovDegrees: 60
                )
            ],
            actions: [
                SceneAction(target: .orbitPath, effect: .drawOrbit, range: 0.1...0.9)
            ]
        )

    private static let gridUnfolds =
        TourBeat(
            id: .gridUnfolds,
            caption: "What if space had static reference points, though? "
                + "What if a grid was laid over the Earth's orbital path…",
            minDuration: 8,
            placeholderDuration: 10,
            camera: [
                // Camera stays locked to the Earth for the whole beat — the
                // grid unfolds around an apparently stationary Earth. The
                // "Earth sails past the grid" reveal belongs to the next
                // beat, once the reference points are all in place.
                CameraKeyframe(
                    progress: 0,
                    frame: .earth,
                    position: SIMD3(0, 30, 45),
                    lookAt: SIMD3(0, 0, -25),
                    fovDegrees: 60
                ),
                CameraKeyframe(
                    progress: 1,
                    frame: .earth,
                    position: SIMD3(0, 27, 40),
                    lookAt: SIMD3(0, 0, -22),
                    fovDegrees: 60
                )
            ],
            actions: [
                SceneAction(target: .spaceGrid, effect: .unfoldGrid, range: 0.0...0.8)
            ]
        )

    /// The wide "watch the markers stream past" framing shared by the final
    /// two beats. The camera tracks the Earth (so it stays put in frame) at a
    /// high, pulled-back angle while the world's grid nodes sail past it — no
    /// dive toward the surface, which is what made the close-up nodes jitter.
    private static let holdPosition = SIMD3<Float>(0, 27, 40)
    private static let holdLookAt = SIMD3<Float>(0, 0, -22)
    private static let holdFov: Float = 60

    private static func holdKeyframe(progress: Double) -> CameraKeyframe {
        CameraKeyframe(
            progress: progress,
            frame: .earth,
            position: holdPosition,
            lookAt: holdLookAt,
            fovDegrees: holdFov
        )
    }

    private static let nodesAppear =
        TourBeat(
            id: .nodesAppear,
            caption: "…and markers placed at regular intervals on this grid, "
                + "that we could see in the sky?",
            minDuration: 7,
            placeholderDuration: 9,
            camera: [holdKeyframe(progress: 0), holdKeyframe(progress: 1)],
            actions: [
                SceneAction(target: .gridNodes, effect: .revealNodes, range: 0.0...0.6)
            ]
        )

    private static let zoomHome =
        TourBeat(
            id: .zoomHome,
            caption: "Now you can look out into the solar system and watch the markers going past at 30km/second.",
            minDuration: 10,
            placeholderDuration: 12,
            // The camera holds the same wide pose the whole beat — the Earth
            // sails on through the grid of markers, then the tour fades to
            // black and hands off to the live sky.
            camera: [holdKeyframe(progress: 0), holdKeyframe(progress: 1)],
            actions: [
                SceneAction(target: .homeMarker, effect: .fadeOpacity(from: 0, to: 1), range: 0.0...0.15)
            ]
        )
}

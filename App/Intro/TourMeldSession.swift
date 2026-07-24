/// Everything one run of the tour owns: the clock, the RealityKit scene, and
/// the meld that hands the tour off to the live AR view. Created when the tour
/// starts and discarded once the intro reaches the live phase, so a replay
/// gets a fresh scene.
@MainActor
final class TourMeldSession {
    let director = TourDirector()
    let renderer = TourRenderer()
    let meld: MeldCoordinator

    init(flow: IntroFlowModel, skyRenderer: SkyRenderer) {
        meld = MeldCoordinator(flow: flow, skyRenderer: skyRenderer)
        flow.liveFrameHandler = { [meld] frame, faceColors, duration in
            meld.applyLiveFrame(frame, faceColors: faceColors, animationDuration: duration)
        }
    }

    func teardown(flow: IntroFlowModel) {
        flow.liveFrameHandler = nil
        // The finish callback is set from the gate and captures this session;
        // clearing it breaks the session → director → closure → session cycle
        // so the tour's ARView and entities actually deallocate.
        director.onFinished = nil
        renderer.stopTicking()
        meld.teardown()
    }
}

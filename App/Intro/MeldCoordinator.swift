import ARKit
import RealityKit
import SwiftUI

/// Drives the tour-to-AR handoff after the final beat (or a skip):
///
/// 1. The tour view fades out to black. The live view beneath shows nothing
///    yet — the camera feed is blacked by the occluder and the node dome is
///    hidden.
/// 2. **Holding for sky** — if the camera isn't pointed a bit above the
///    horizon, a prompt asks for it; hysteresis and a short dwell keep the
///    transition from strobing.
/// 3. **Revealing** — the calculated nodes fade in at their true sky
///    positions while the feed occluder fades out behind them; then the
///    chrome appears and the app is in its normal steady state.
@MainActor
final class MeldCoordinator {
    private enum Stage: Equatable {
        case idle
        case holdingForSky
        case revealing
        case done
    }

    private let flow: IntroFlowModel
    private let skyRenderer: SkyRenderer

    private var stage: Stage = .idle
    private var pointingTask: Task<Void, Never>?
    private var latestFrame: SkyFrame?
    private var pointingAboveSince: Date?
    private var pointingNoNodesSince: Date?

    init(flow: IntroFlowModel, skyRenderer: SkyRenderer) {
        self.flow = flow
        self.skyRenderer = skyRenderer
    }

    /// The director finished the final beat: fade the tour and wait for sky.
    func tourDidFinish() {
        guard stage == .idle else { return }
        enterHoldingForSky(advancingFlow: true)
    }

    /// User skipped: same path, `IntroFlowModel.tourSkipped` already moved the
    /// phase.
    func skip() {
        guard stage != .revealing, stage != .done else { return }
        enterHoldingForSky(advancingFlow: false)
    }

    /// Live-tick sink: keeps the latest frame around for the "any nodes above
    /// the horizon" check.
    func applyLiveFrame(_ frame: SkyFrame, faceColors: [Color.Resolved], animationDuration: TimeInterval) {
        latestFrame = frame
    }

    func teardown() {
        pointingTask?.cancel()
        pointingTask = nil
        stage = .done
    }

    // MARK: - Sky pointing + reveal

    private func enterHoldingForSky(advancingFlow: Bool) {
        guard stage != .holdingForSky else { return }
        stage = .holdingForSky
        pointingAboveSince = nil
        pointingNoNodesSince = nil
        if advancingFlow {
            flow.advanceMeld(to: .holdingForSky)
        }
        pointingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.stage == .holdingForSky else { return }
                self.evaluatePointing()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    private func evaluatePointing() {
        let elevation = SkyPointingMonitor.cameraElevationDegrees(skyRenderer.arView.cameraTransform)
        guard elevation >= TourTuning.skyEnterElevationDegrees else {
            if elevation < TourTuning.skyExitElevationDegrees {
                pointingAboveSince = nil
                pointingNoNodesSince = nil
            }
            return
        }

        let now = Date.now
        if pointingAboveSince == nil { pointingAboveSince = now }
        guard let since = pointingAboveSince, now.timeIntervalSince(since) >= TourTuning.skyDwellSeconds else {
            return
        }

        // Pointing over the horizon is the gate; the node check only guards
        // the pathological all-below-horizon configuration.
        if let frame = latestFrame, frame.stats.aboveHorizonCount > 0 {
            beginReveal()
        } else {
            if pointingNoNodesSince == nil { pointingNoNodesSince = now }
            if let noNodes = pointingNoNodesSince,
               now.timeIntervalSince(noNodes) >= TourTuning.skyNoNodesTimeoutSeconds {
                Log.warn("intro.meld.revealWithoutNodes")
                beginReveal()
            }
        }
    }

    private func beginReveal() {
        guard stage == .holdingForSky else { return }
        stage = .revealing
        pointingTask?.cancel()
        pointingTask = nil
        flow.advanceMeld(to: .revealing)
        skyRenderer.revealDome(duration: TourTuning.domeFadeInSeconds)
        skyRenderer.revealFeed(duration: TourTuning.meldRevealSeconds)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(TourTuning.meldRevealSeconds + 0.2))
            guard let self, self.stage == .revealing else { return }
            self.stage = .done
            self.flow.advanceMeld(to: .live)
        }
    }
}

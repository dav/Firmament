import Observation
import SwiftUI

/// Drives the first-launch experience: decides whether the intro runs at all,
/// owns the current `IntroPhase`, and marks the intro as seen when the user
/// finishes or skips. The meld phases between `touring` and `live` are
/// advanced by `MeldCoordinator` through `advanceMeld(to:)`.
@MainActor
@Observable
final class IntroFlowModel {
    private(set) var phase: IntroPhase

    /// Set while a tour session exists; `ContentView`'s tick hands each live
    /// `SkyFrame` to the meld through this so both scenes render the same sky.
    var liveFrameHandler: ((SkyFrame, [Color.Resolved], TimeInterval) -> Void)?

    private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        let showIntro: Bool
        #if DEBUG
        showIntro = !settings.hasSeenIntro || settings.debugAlwaysShowIntro
        #else
        showIntro = !settings.hasSeenIntro
        #endif
        phase = showIntro ? .permissions : .live
    }

    /// Called once from the gate's `.task` — SwiftUI re-runs view inits on
    /// every parent render, so logging can't live in `init`.
    func logGateDecision() {
        Log.info("intro.gate", [
            "show_intro": phase != .live,
            "reason": phase != .live
                ? (settings.hasSeenIntro ? "debug_toggle" : "first_launch")
                : "seen"
        ])
    }

    var isIntroActive: Bool { phase != .live }
    var isChromeVisible: Bool { phase == .live }
    /// Whether the live dome needs per-tick astronomy updates. While the tour
    /// plays the live view sits hidden behind the opaque tour (it must stay
    /// mounted — see ContentView — but there's nothing to update); ticks
    /// resume once the tour ends and one tick fully repopulates the dome.
    var isLiveDomeActive: Bool {
        switch phase {
        case .permissions, .touring: false
        case .holdingForSky, .revealing, .live: true
        }
    }
    var isTourPresented: Bool { phase == .touring }

    func permissionsCompleted() {
        guard phase == .permissions else { return }
        phase = .touring
    }

    /// "Skip tour" from the primer: grant-and-go straight to the live view,
    /// bypassing the whole animated intro and its sky-pointing handoff.
    func skipTourFromPermissions() {
        guard phase == .permissions else { return }
        endTourState()
        Log.info("intro.skipTour")
        phase = .live
        Log.info("intro.finished")
    }

    /// Skip cuts through black: the tour view fades out and the flow joins the
    /// meld pipeline at the sky-pointing gate.
    func tourSkipped(atTime time: Double, beat: String) {
        endTourState()
        Log.info("intro.skip", ["at_time_s": time, "beat": beat])
        withAnimation(.easeOut(duration: 0.3)) {
            phase = .holdingForSky
        }
    }

    /// Meld-driven phase progression: holdingForSky → revealing → live. The
    /// step out of `touring` animates so the tour view cross-fades to black.
    func advanceMeld(to newPhase: IntroPhase) {
        guard newPhase != phase else { return }
        if phase == .touring {
            endTourState()
            withAnimation(.easeOut(duration: 0.6)) {
                phase = newPhase
            }
        } else {
            phase = newPhase
        }
        Log.info("intro.meld.phase", ["phase": "\(newPhase)"])
        if newPhase == .live {
            Log.info("intro.finished")
        }
    }

    /// Shared bookkeeping whenever the tour ends (finished, skipped, or
    /// skipped from the primer): mark it seen and land the user in Grid mode
    /// with the Earth occluding below-horizon nodes, regardless of what they
    /// had selected before, per the intro's design.
    private func endTourState() {
        settings.hasSeenIntro = true
        settings.renderMode = .grid
        settings.showBelowHorizon = false
    }

    func replay() {
        Log.info("intro.replay")
        phase = .touring
    }
}

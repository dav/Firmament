import ARKit

/// Logs only the low-frequency, transition-style ARSession signals worth
/// debugging — failures, interruptions, and camera tracking-state changes — and
/// notifies the renderer so it can recover from a failed session. Deliberately
/// does not implement `session(_:didUpdate:)`, which fires every frame.
///
/// `@unchecked Sendable`: the callbacks are set once on the main actor before the
/// session starts and never mutated afterward, so the reads from ARKit's delegate
/// queue race with nothing.
final class ARSessionObserver: NSObject, ARSessionDelegate, @unchecked Sendable {
    var onSessionFailed: (@MainActor @Sendable () -> Void)?
    /// Called with `true` when tracking reaches `.normal`, `false` when it
    /// degrades — the intro meld gates its camera handoff on this.
    var onTrackingStateChanged: (@MainActor @Sendable (Bool) -> Void)?

    func session(_ session: ARSession, didFailWithError error: Error) {
        Log.error("ar.session.failed", ["error": error.localizedDescription])
        if let onSessionFailed { Task { @MainActor in onSessionFailed() } }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        Log.warn("ar.session.interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        Log.info("ar.session.interruptionEnded")
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        // Fires only when the tracking state actually changes, so this is a good
        // signal for "why did the sky drift / freeze" without per-frame noise.
        let isNormal: Bool
        switch camera.trackingState {
        case .normal:
            Log.info("ar.trackingState", ["state": "normal"])
            isNormal = true
        case .notAvailable:
            Log.warn("ar.trackingState", ["state": "notAvailable"])
            isNormal = false
        case .limited(let reason):
            Log.warn("ar.trackingState", ["state": "limited", "reason": Self.reasonName(reason)])
            isNormal = false
        }
        if let onTrackingStateChanged { Task { @MainActor in onTrackingStateChanged(isNormal) } }
    }

    private static func reasonName(_ reason: ARCamera.TrackingState.Reason) -> String {
        switch reason {
        case .initializing: "initializing"
        case .relocalizing: "relocalizing"
        case .excessiveMotion: "excessiveMotion"
        case .insufficientFeatures: "insufficientFeatures"
        @unknown default: "unknown"
        }
    }
}

/// The first-launch experience state machine, from permission priming through
/// the animated tour and its handoff to the live AR view.
///
/// `holdingForSky` and `revealing` are the handoff phases: the tour has faded
/// to black, the app waits for the camera to point above the horizon, then
/// the calculated nodes fade in and the camera feed follows.
nonisolated enum IntroPhase: Equatable, Sendable {
    /// Black screen requesting camera + location up front, before the tour.
    case permissions
    /// The scripted animated tour is playing.
    case touring
    /// Tour gone; waiting for the camera to point at the sky.
    case holdingForSky
    /// Nodes fading in and the feed occluder fading out behind them.
    case revealing
    /// Normal AR app.
    case live
}

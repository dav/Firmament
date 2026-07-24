/// A tour scene element (or element group) that actions can target.
nonisolated enum TourEntityID: Hashable, Sendable, CaseIterable {
    case grass
    case posts
    case trackEdgeLines
    case trackPavement
    case car
    /// The hood ornament's little Earth globe — kept separate from `car` so it
    /// can survive the car's fade and morph into the real Earth.
    case ornamentGlobe
    case earth
    case sun
    case orbitPath
    case spaceGrid
    case gridNodes
    case homeMarker
    case worldRig
}

/// What an action does to its target as its progress runs 0 → 1.
nonisolated enum TourEffect: Sendable {
    /// Interpolates the target's opacity. Reveals and hides are both this,
    /// so visibility at any time is a pure function of the action history.
    case fadeOpacity(from: Float, to: Float)
    /// Draws the orbital path on, as a fraction of the full circle.
    case drawOrbit
    /// Unfolds the space grid outward from the sun toward Earth's orbit.
    case unfoldGrid
    /// Reveals the lattice-node cubes, nearest bands first.
    case revealNodes
    /// Ramps the target's uniform scale geometrically from → to (used for the
    /// world-rig approach ramp in the final beats).
    case rampScale(from: Float, to: Float)
}

/// One scripted effect over a window of a beat's progress.
nonisolated struct SceneAction: Sendable {
    let target: TourEntityID
    let effect: TourEffect
    /// The beat-progress window the effect runs across.
    let range: ClosedRange<Double>
    let easing: TourEasing

    init(
        target: TourEntityID,
        effect: TourEffect,
        range: ClosedRange<Double>,
        easing: TourEasing = .easeInOut
    ) {
        self.target = target
        self.effect = effect
        self.range = range
        self.easing = easing
    }
}

/// An action with its eased progress at the sampled time: 0 before its window,
/// 1 after it (including in all later beats), interpolated inside it. Every
/// sample carries the values for *all* actions in the script, in script order,
/// so scene state rebuilt from a single sample is scrub-safe.
nonisolated struct ResolvedActionValue: Sendable {
    let target: TourEntityID
    let effect: TourEffect
    let progress: Double
}

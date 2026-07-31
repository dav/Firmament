import FirmamentCore
import RealityKit

/// Where the dropped flare sits on the dome this tick, and where it is headed by
/// the next one — the flare's counterpart to `NodePlacement`.
nonisolated struct FlarePlacement: Sendable {
    let nowPosition: SIMD3<Float>
    let nowDiameter: Float
    let targetPosition: SIMD3<Float>
    let targetDiameter: Float
    /// Where the distance label hangs: the flare's own sky direction, dropped
    /// far enough below the ball to clear it, and pulled well inside the dome so
    /// nothing can occlude it.
    let labelPosition: SIMD3<Float>
    /// Uniform scale that holds the label at a constant angular size.
    let labelScale: Float
    let distanceKm: Double
    let isBelowHorizon: Bool
    /// Past the cutoff the lattice itself respects — the Earth is between the
    /// observer and the flare, and x-ray mode is off. The distance readout in
    /// the chrome keeps running; only the sphere and its label go away.
    let isHidden: Bool
}

/// The flare's placement math. Pure and off-main like the rest of
/// `SkyRendererCompute`, and it reuses the same dome mapping as the node cubes,
/// so the flare sinks through the lattice at the depth its true distance earns.
extension SkyRenderer {
    /// A just-dropped flare is metres away and angularly enormous; without a cap
    /// it would swallow the camera. Capped as a fraction of its dome radius.
    nonisolated static let maxFlareDiameterFraction = 0.9
    /// Never let the flare shrink to a degenerate scale — the label carries it
    /// once the ball itself is under a pixel.
    nonisolated static let minFlareDiameterMeters: Float = 0.05
    /// Nothing renders until the flare is this far off. At 30 km/s that is a few
    /// hundredths of a second, and it keeps the sky direction out of the
    /// numerical noise around zero separation.
    nonisolated static let minFlareDistanceKm = 1.0
    /// The label hangs this fraction of the way in from the flare's dome shell,
    /// so it always draws in front of the dome's cubes and lines.
    nonisolated static let flareLabelDepthFraction = 0.5
    /// Angular gap between the bottom of the ball and the top of the label.
    nonisolated static let flareLabelGapRadians = 2.5 * .pi / 180
    /// However big the ball gets, the label never drops further than this below
    /// it — otherwise a fresh flare would fling its own label off-screen.
    nonisolated static let maxFlareLabelDropRadians = 10.0 * .pi / 180
    /// On-screen height of the label, radians. Constant at every dome radius.
    nonisolated static let flareLabelAngularHeight = 2.6 * .pi / 180

    /// Where a flare dropped this instant would fall to. A flare *is* the
    /// observer's present position seen from their near future, so the aim
    /// target falls straight out of the two observer states the tick already has.
    nonisolated static func flareDropTarget(
        observer: ObserverState,
        futureObserver: ObserverState
    ) -> FlareDropTarget {
        let direction = Firmament.skyDirection(
            toHeliocentricKm: observer.heliocentricPositionKm,
            observer: futureObserver
        )
        return FlareDropTarget(
            azimuthRadians: direction.azimuthRadians,
            elevationRadians: direction.elevationRadians
        )
    }

    nonisolated static func flarePlacement(
        flare: DroppedFlare,
        observer: ObserverState,
        futureObserver: ObserverState,
        range: DistanceRange,
        minElevation: Double
    ) -> FlarePlacement? {
        let now = Firmament.skyDirection(toHeliocentricKm: flare.heliocentricKm, observer: observer)
        guard now.distanceKm >= minFlareDistanceKm else { return nil }
        let next = Firmament.skyDirection(toHeliocentricKm: flare.heliocentricKm, observer: futureObserver)

        let current = flareDomePlacement(for: now, range: range)
        let target = flareDomePlacement(for: next, range: range)
        let (labelPosition, labelScale) = flareLabelPlacement(
            ballPosition: current.position,
            ballDiameter: current.diameter,
            radius: domeRadius(forDistanceKm: now.distanceKm, range: range)
        )

        return FlarePlacement(
            nowPosition: current.position,
            nowDiameter: current.diameter,
            targetPosition: target.position,
            targetDiameter: target.diameter,
            labelPosition: labelPosition,
            labelScale: labelScale,
            distanceKm: now.distanceKm,
            isBelowHorizon: now.elevationRadians < 0,
            isHidden: now.elevationRadians < minElevation
        )
    }

    /// Dome position and rendered diameter, mapped exactly like a node cube:
    /// true angular size at the node's own dome radius.
    private nonisolated static func flareDomePlacement(
        for direction: SkyDirection,
        range: DistanceRange
    ) -> (position: SIMD3<Float>, diameter: Float) {
        let radius = domeRadius(forDistanceKm: direction.distanceKm, range: range)
        let position = domeDirection(
            azimuthRadians: direction.azimuthRadians,
            elevationRadians: direction.elevationRadians
        ) * Float(radius)
        let apparentDiameter = radius * DroppedFlare.diameterKm / max(direction.distanceKm, minFlareDistanceKm)
        let capped = min(apparentDiameter, radius * maxFlareDiameterFraction)
        return (position, max(Float(capped), minFlareDiameterMeters))
    }

    /// Hangs the label directly below the ball by rotating the flare's sky
    /// direction downward, then pulling the result in toward the camera. Working
    /// in angles keeps the gap consistent whether the ball fills the view or is
    /// a speck.
    private nonisolated static func flareLabelPlacement(
        ballPosition: SIMD3<Float>,
        ballDiameter: Float,
        radius: Double
    ) -> (position: SIMD3<Float>, scale: Float) {
        let direction = normalize(ballPosition)
        let ballAngularRadius = atan(Double(ballDiameter) / 2 / radius)
        let drop = min(ballAngularRadius, maxFlareLabelDropRadians) + flareLabelGapRadians

        // The "up" direction as seen at the flare: world up with the component
        // along the sight line removed. Degenerate when the flare is at the
        // zenith or nadir, where any perpendicular will do.
        let reference: SIMD3<Float> = abs(direction.y) > 0.999 ? SIMD3(0, 0, -1) : SIMD3(0, 1, 0)
        let localUp = normalize(reference - direction * dot(reference, direction))
        let labelDirection = direction * Float(cos(drop)) - localUp * Float(sin(drop))

        let labelRadius = radius * flareLabelDepthFraction
        let scale = labelRadius * flareLabelAngularHeight / Double(FlareEntities.labelFontSize)
        return (normalize(labelDirection) * Float(labelRadius), Float(scale))
    }
}

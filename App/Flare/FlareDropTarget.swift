import Foundation

/// Where in the local sky a flare dropped *right now* would end up: astern,
/// along the direction Earth is carrying the observer away from.
///
/// Computed each tick by asking where the observer's present position will
/// appear to the observer a moment from now — which is exactly what a flare is.
nonisolated struct FlareDropTarget: Sendable, Equatable {
    /// Radians clockwise from true north.
    let azimuthRadians: Double
    /// Radians above the local horizon; negative means behind the Earth.
    let elevationRadians: Double

    static let unknown = FlareDropTarget(azimuthRadians: 0, elevationRadians: 0)
}

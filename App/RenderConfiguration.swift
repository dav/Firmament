import FirmamentCore
import SwiftUI

/// Which node layout the renderer draws.
nonisolated enum RenderMode: String, CaseIterable, Sendable {
    /// The evenly spaced orthogonal lattice.
    case grid
    /// Rings of nodes on a big tube around Earth's orbital path (see `OrbitTube`).
    case tube
    /// The same tube threaded through the observer, tight enough that rings
    /// arch right overhead — a ride down Earth's orbit.
    case ride
}

/// A value snapshot of every setting the renderer needs for one update pass.
/// `nonisolated Sendable` so it can be handed to the off-main frame computation.
nonisolated struct RenderConfiguration: Equatable, Sendable {
    var renderMode: RenderMode
    var unitSpacingKm: Double
    /// Candidate-volume reach within the ecliptic (orbital) plane, km.
    /// In tube mode this doubles as the reach along the tube.
    var inPlaneRadiusKm: Double
    /// Candidate-volume reach above/below the ecliptic plane, km.
    var outOfPlaneHalfExtentKm: Double
    /// The active tube radius — `AppSettings` fills in the tube- or ride-mode
    /// value to match `renderMode`.
    var tubeRadiusKm: Double
    var tubeNodesPerRing: Int
    var cubeEdgeKm: Double
    /// The active tube-family cube edge, chosen per mode like `tubeRadiusKm`:
    /// tube-mode walls sit thousands of km away and need big cubes; ride-mode
    /// walls are tens of km away and need small ones.
    var tubeCubeEdgeKm: Double
    var ghostBandDegrees: Double
    var showGhostNodes: Bool
    /// X-ray mode: include everything below the horizon, rendered ghost-style.
    var showBelowHorizon: Bool
    var faceColors: [Color.Resolved]

    /// Ring node count forced even (two nodes always on the ecliptic plane).
    var sanitizedNodesPerRing: Int {
        OrbitTube.sanitizedNodesPerRing(tubeNodesPerRing)
    }
}

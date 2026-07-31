import FirmamentCore
import Foundation

/// A marker dropped at the observer's own position in the lattice.
///
/// Its heliocentric point is fixed the instant it is dropped and never moves
/// again — the observer does, at roughly 30 km/s along Earth's orbit. So the
/// flare falls astern within seconds, which is the whole point of it: the
/// lattice's motion made personal, with a number attached.
nonisolated struct DroppedFlare: Sendable, Equatable {
    /// Where the observer stood, in the ecliptic-of-date inertial frame, at the
    /// moment of the drop. Fixed for the flare's whole life.
    let heliocentricKm: Vector3
    let droppedAt: Date

    /// Diameter of the rendered sphere, km. Sized against the lattice's 10 km
    /// grid cubes: small enough to read as *an object you left behind* rather
    /// than a piece of the grid.
    static let diameterKm = 1.0
}

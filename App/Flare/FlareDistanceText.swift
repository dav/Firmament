import Foundation

/// The one place the flare's distance becomes text, so the chip in the chrome
/// and the label hanging in the sky always read the same.
nonisolated enum FlareDistanceText {
    /// A decimal while the flare is still close enough for whole kilometres to
    /// look frozen; whole kilometres from there on, where they tick over fast.
    static func kilometers(_ distanceKm: Double) -> String {
        let amount = distanceKm < 10
            ? distanceKm.formatted(.number.precision(.fractionLength(1)))
            : distanceKm.formatted(.number.precision(.fractionLength(0)))
        return "\(amount) km"
    }
}

import SwiftUI

/// Drops a flare at the observer's own position, and removes it again. While one
/// is out, a chip above the button carries its distance — the same number the
/// label in the sky shows, for when the flare has fallen behind you.
///
/// While the aim guide is up and the camera is still off target the button goes
/// inert and turns into a sight, so "armed" is something the user can see.
struct FlareControl: View {
    let isDropped: Bool
    let distanceKm: Double?
    let canDrop: Bool
    let isAwaitingAim: Bool
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let distanceKm {
                Text(FlareDistanceText.kilometers(distanceKm))
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
            }
            Button(action: onToggle) {
                Image(systemName: symbolName)
                    .font(.title2)
                    .padding(2)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .disabled(!isDropped && (!canDrop || isAwaitingAim))
            .accessibilityLabel(accessibilityLabel)
        }
        .animation(.easeInOut(duration: 0.2), value: distanceKm == nil)
        .animation(.easeInOut(duration: 0.2), value: isAwaitingAim)
    }

    private var symbolName: String {
        if isDropped { return "xmark" }
        return isAwaitingAim ? "scope" : "flame.fill"
    }

    private var accessibilityLabel: String {
        if isDropped { return "Remove the flare" }
        return isAwaitingAim ? "Aim the camera astern to arm the flare" : "Drop a flare here"
    }
}

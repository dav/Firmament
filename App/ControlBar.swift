import SwiftUI

/// The bottom overlay row: flare drop/remove on the left, layout mode pill
/// centered, Earth-occlusion toggle on the right.
struct ControlBar: View {
    @Binding var showBelowHorizon: Bool
    @Binding var renderMode: RenderMode
    let isFlareDropped: Bool
    let flareDistanceKm: Double?
    let canDropFlare: Bool
    /// The aim guide is up and the camera hasn't come round yet.
    let isAwaitingAim: Bool
    let onToggleFlare: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(alignment: .bottom) {
                FlareControl(
                    isDropped: isFlareDropped,
                    distanceKm: flareDistanceKm,
                    canDrop: canDropFlare,
                    isAwaitingAim: isAwaitingAim,
                    onToggle: onToggleFlare
                )

                Spacer()

                Button {
                    showBelowHorizon.toggle()
                } label: {
                    Image(systemName: showBelowHorizon ? "circle.dashed" : "circle.bottomhalf.filled")
                        .font(.title2)
                        .padding(2)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .accessibilityLabel(
                    showBelowHorizon ? "Enable Earth occlusion" : "Show nodes below the horizon"
                )
            }
            RenderModePicker(mode: $renderMode)
        }
    }
}

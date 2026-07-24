import SwiftUI

/// The bottom overlay row: layout mode pill centered, Earth-occlusion toggle
/// on the right.
struct ControlBar: View {
    @Binding var showBelowHorizon: Bool
    @Binding var renderMode: RenderMode

    var body: some View {
        ZStack {
            HStack {
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

import SwiftUI

/// The bottom-center pill that switches between the grid and tube layouts.
struct RenderModePicker: View {
    @Binding var mode: RenderMode

    var body: some View {
        HStack(spacing: 4) {
            segment("Grid", .grid)
            segment("Tube", .tube)
            segment("Ride", .ride)
        }
        .padding(4)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func segment(_ title: String, _ value: RenderMode) -> some View {
        Button {
            mode = value
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(mode == value ? .primary : .secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if mode == value {
                        Capsule().fill(.white.opacity(0.35))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) layout")
        .accessibilityAddTraits(mode == value ? .isSelected : [])
    }
}

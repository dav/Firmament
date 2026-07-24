import SwiftUI

/// A compact scale readout: the cube size actually rendered and the true gaps
/// between neighboring nodes. Tube and ride modes add the ring spacing, and
/// tube mode flags it whenever the exact-spacing rings are all below the
/// horizon — so the numbers always describe what's actually on screen.
struct ScaleHUD: View {
    let info: ScaleInfo
    let mode: RenderMode
    let isNearRingWindowVisible: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row("Cube size", info.cubeEdgeKm)
            row("Between cubes", info.betweenCubesKm)
            if mode != .grid {
                row(
                    "Between rings",
                    info.betweenRingsKm,
                    note: isNearRingWindowVisible ? nil : "below horizon"
                )
                if let farGap = info.farRingGapKm {
                    row("Distant rings", farGap)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func row(_ label: String, _ kilometers: Double, note: String? = nil) -> some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundStyle(.secondary)
            Text("\(kilometers, format: format(for: kilometers)) km")
            if let note {
                Text("· \(note)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func format(for kilometers: Double) -> FloatingPointFormatStyle<Double> {
        .number.precision(.fractionLength(kilometers < 10 ? 1 : 0))
    }
}

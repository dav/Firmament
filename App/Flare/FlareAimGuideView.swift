import SwiftUI

/// Talks the user round to face the spot a flare would fall to. Appears when
/// they tap the flare button while pointed somewhere else, and stays up —
/// updating live — until they drop the flare or back out.
struct FlareAimGuideView: View {
    let aim: FlareAim
    let showBelowHorizon: Bool
    let onDisableOcclusion: () -> Void
    let onCancel: () -> Void

    private var isReady: Bool {
        aim.isOnTarget && !aim.needsXRay(showBelowHorizon: showBelowHorizon)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                isReady ? "On target" : "Look astern",
                systemImage: isReady ? "checkmark.circle.fill" : "scope"
            )
            .font(.subheadline.bold())
            .foregroundStyle(isReady ? .green : .primary)

            if isReady {
                Text("Tap the flare button to drop it here.")
                    .font(.footnote)
            } else {
                Text(
                    """
                    A flare stays where you leave it while Earth carries you off \
                    at 30 km/s — so it falls behind you. Point the camera back \
                    along your path.
                    """
                )
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                ForEach(aim.instructions) { instruction in
                    Label(instruction.text, systemImage: instruction.systemImage)
                        .font(.footnote.monospacedDigit())
                }
            }

            if aim.isBelowHorizon {
                FlareAimOcclusionNotice(
                    depthBelowHorizonDegrees: -aim.targetElevationRadians * 180 / .pi,
                    isOcclusionOff: showBelowHorizon,
                    onDisableOcclusion: onDisableOcclusion
                )
            }

            Button("Cancel", action: onCancel)
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 280, alignment: .leading)
        .padding(14)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
    }
}

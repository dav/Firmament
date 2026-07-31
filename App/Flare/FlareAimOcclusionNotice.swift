import SwiftUI

/// The drop point is under the horizon: the Earth is between the user and the
/// spot their flare would fall to.
///
/// Normally the guide has already switched occlusion off by the time this
/// appears, so it just says why the ground has gone see-through. The button
/// only comes back if the user turns occlusion on again while aiming — the
/// flare needs it off to be watchable at all.
struct FlareAimOcclusionNotice: View {
    let depthBelowHorizonDegrees: Double
    let isOcclusionOff: Bool
    let onDisableOcclusion: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: "globe.americas.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if !isOcclusionOff {
                Button(
                    "Turn off Earth occlusion",
                    systemImage: "circle.dashed",
                    action: onDisableOcclusion
                )
                .font(.footnote.weight(.medium))
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
            }
        }
    }

    private var message: String {
        let depth = depthBelowHorizonDegrees.formatted(.number.precision(.fractionLength(0)))
        if isOcclusionOff {
            return """
                That spot is \(depth)° below the horizon, so Earth occlusion is off \
                — follow the grid down through the ground and the flare will be there.
                """
        }
        return """
            That spot is \(depth)° below the horizon and the Earth is in the way. \
            Occlusion has to be off to watch a flare down there.
            """
    }
}

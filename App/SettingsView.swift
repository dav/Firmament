import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    var onReplayIntro: () -> Void = {}
    @Environment(\.self) private var environment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                cubeSection
                horizonSection
                introSection
                resetSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var cubeSection: some View {
        Section {
            ForEach(CubeFace.allCases) { face in
                ColorPicker(face.label, selection: faceColorBinding(for: face), supportsOpacity: false)
            }
        } header: {
            Text("Cube Colors")
        } footer: {
            Text(
                "Every cube is aligned to the lattice axes, so all faces pointing the same way share a "
                    + "color: the x faces point at the equinox points, the y faces at the solstice points "
                    + "90° along the ecliptic, and the z faces at the ecliptic poles."
            )
        }
    }

    private var horizonSection: some View {
        Section {
            Toggle("Show nodes just below horizon", isOn: $settings.showGhostNodes)
            if settings.showGhostNodes {
                LabeledSlider(
                    title: "Ghost band",
                    value: $settings.ghostBandDegrees,
                    range: 1...15,
                    step: 1,
                    unit: "°"
                )
            }
        } header: {
            Text("Horizon")
        } footer: {
            Text(
                "Nodes below the horizon are hidden by the Earth itself. The ghost band renders nodes "
                    + "slightly below it as translucent, so the lattice structure still reads near the horizon."
            )
        }
    }

    private var introSection: some View {
        Section {
            Button("Replay intro") {
                dismiss()
                onReplayIntro()
            }
            #if DEBUG
            Toggle("Always show intro on launch", isOn: $settings.debugAlwaysShowIntro)
            #endif
        } header: {
            Text("Intro")
        } footer: {
            Text("Replays the first-launch tour of what Firmament shows and why.")
        }
    }

    private var resetSection: some View {
        Section {
            Button("Reset to Defaults", role: .destructive) {
                settings.resetToDefaults()
            }
        }
    }

    private func faceColorBinding(for face: CubeFace) -> Binding<Color> {
        Binding(
            get: { Color(settings.faceColors[face.rawValue]) },
            set: { settings.faceColors[face.rawValue] = $0.resolve(in: environment) }
        )
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var fractionDigits = 0

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(title)
                Spacer()
                Text("\(value, format: .number.precision(.fractionLength(fractionDigits))) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: $value, in: range, step: step)
        }
    }
}

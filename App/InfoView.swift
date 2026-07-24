import SwiftUI

struct InfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingFullSign = false

    var body: some View {
        NavigationStack {
            ScrollView {
                Image("FirmamentTitle")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { isShowingFullSign = true }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Dav's Celestial Firmament")
                    .accessibilityHint("Shows the full sign")
                VStack(alignment: .leading, spacing: 20) {
                    InfoBlock(
                        title: "What am I looking at?",
                        text: "Imagine the solar system threaded with an enormous, perfectly regular 3D grid "
                            + "of markers, fixed relative to the distant stars. The grid never moves — but Earth "
                            + "does. It spins once a day and races along its orbit at about 30 km/s, so the grid "
                            + "is constantly sweeping past you. This app computes which grid nodes are above your "
                            + "horizon right now and draws them over the camera view, exactly where they are."
                    )
                    InfoBlock(
                        title: "Why do the cubes drift?",
                        text: "They aren't, you and the Earth are drifting past them."
                    )
                    InfoBlock(
                        title: "How it works",
                        text: "Using your GPS position and the current time, the app computes your position "
                            + "relative to the Sun's center — the lattice origin — with a solar ephemeris accurate "
                            + "to about an arcminute. Each nearby node is projected into your local sky; anything "
                            + "below the horizon is hidden behind the Earth itself (unless you switch off "
                            + "occlusion mode). Cube size shrinks with true distance, so small cubes really "
                            + "are farther away."
                    )
                    InfoBlock(
                        title: "The colors",
                        text: "Every cube is aligned to the grid axes, and each of its six faces has its "
                            + "own color (change them in Settings if you like): one face pair points at the "
                            + "equinox points, one at the solstice points, and one at the ecliptic poles. "
                            + "Cubes brighten toward the Sun's direction and dim away from it. Nodes lying exactly on "
                            + "the ecliptic plane render white with black edges."
                    )
                    InfoBlock(
                        title: "The grid and Earth's orbit",
                        text: "Two grid axes span Earth's orbital plane and the third points at right angles "
                            + "out of it, so all of Earth's orbital motion sweeps along the grid's x-y plane. "
                            + "One axis of the orbital plane points toward the vernal equinox "
                            + "(the First Point of Aries). A translucent orange sphere always marks the "
                            + "Sun's true position in the center of the orbital plane."
                    )
                    InfoBlock(
                        title: "Three layouts",
                        text: "The pill at the bottom switches between three views of the same idea. "
                            + "Grid threads space with a regular lattice of cubes. Tube floats Earth "
                            + "inside a wide ring-lined bore following its orbit around the Sun, with "
                            + "distant rings sketched as outlines receding fore and aft. You move towards "
                            + " or away from the orbital tube throughout the day as the Earth rotates. "
                            + "Ride threads "
                            + "that same tunnel idea but through you as the center: rings arch overhead just tens of "
                            + "kilometers up, and Earth's motion carries you through."
                    )
                    InfoBlock(
                        title: "A tip on accuracy",
                        text: "The math is far more precise than your phone's compass. If the lattice seems "
                            + "rotated, move away from metal and magnets and wave your phone in a figure-eight to "
                            + "recalibrate the compass, then restart the AR view."
                    )
                }
                .padding()
            }
            .navigationTitle("Dav's Firmament")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $isShowingFullSign) {
                FullSignView()
            }
        }
    }
}

/// The full "Dav's Celestial Firmament" sign, shown when the title image on the
/// Info screen is tapped. Tap anywhere or the close button to dismiss.
private struct FullSignView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Image("LaunchImage")
                .resizable()
                .scaledToFit()
                .accessibilityLabel("Dav's Celestial Firmament")
            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.white)
                            .padding()
                    }
                    .accessibilityLabel("Close")
                }
                Spacer()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { dismiss() }
    }
}

struct InfoBlock: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(text)
                .foregroundStyle(.secondary)
        }
    }
}

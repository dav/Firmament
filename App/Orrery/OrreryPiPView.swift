import RealityKit
import SwiftUI

/// The collapsible picture-in-picture orrery: a small window over the live AR
/// view showing the intro tour's "Earth streaming through the markers" shot,
/// live, with the node layout matching the current render mode — so what
/// drifts past in the sky can be matched to Earth seen from afar.
struct OrreryPiP: View {
    let settings: AppSettings
    let locationProvider: LocationProvider

    /// Exists exactly while expanded — collapsing tears the renderer (and its
    /// second RealityKit surface) down entirely, so the collapsed PiP costs
    /// nothing.
    @State private var renderer: OrreryRenderer?

    var body: some View {
        Group {
            if let renderer {
                expandedWindow(renderer)
            } else {
                expandButton
            }
        }
        .onAppear(perform: syncRenderer)
        .onDisappear {
            renderer?.stop()
            renderer = nil
        }
        .onChange(of: settings.isOrreryExpanded) { _, _ in syncRenderer() }
        .onChange(of: settings.renderMode) { _, mode in renderer?.setMode(mode) }
        .animation(.easeInOut(duration: 0.2), value: settings.isOrreryExpanded)
    }

    private func expandedWindow(_ renderer: OrreryRenderer) -> some View {
        ZStack(alignment: .topTrailing) {
            OrrerySkyView(renderer: renderer)
                .frame(width: 220, height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )
            Button {
                settings.isOrreryExpanded = false
            } label: {
                Image(systemName: "chevron.down")
                    .font(.footnote)
                    .padding(5)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .padding(6)
            .accessibilityLabel("Collapse orbit view")
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomTrailing)))
    }

    private var expandButton: some View {
        Button {
            settings.isOrreryExpanded = true
        } label: {
            Image(systemName: "globe.americas.fill")
                .font(.title2)
                .padding(2)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Show orbit view")
        .transition(.opacity)
    }

    private func syncRenderer() {
        if settings.isOrreryExpanded {
            guard renderer == nil else { return }
            let built = OrreryRenderer(
                mode: settings.renderMode,
                homeLatitudeDegrees: locationProvider.fix?.latitudeDegrees,
                homeLongitudeDegrees: locationProvider.fix?.longitudeDegrees
            )
            built.start()
            renderer = built
            Log.info("ui.orrery.expand", ["mode": settings.renderMode.rawValue])
        } else if renderer != nil {
            renderer?.stop()
            renderer = nil
            Log.info("ui.orrery.collapse")
        }
    }
}

/// Mounts the orrery's `ARView`. Rendering works because the session-backed
/// live `ARSkyView` is always mounted alongside it (same constraint as the
/// tour's non-AR view).
private struct OrrerySkyView: UIViewRepresentable {
    let renderer: OrreryRenderer

    func makeUIView(context: Context) -> ARView {
        renderer.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

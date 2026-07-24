import RealityKit
import SwiftUI

struct TourSkyView: UIViewRepresentable {
    let renderer: TourRenderer

    func makeUIView(context: Context) -> ARView {
        renderer.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

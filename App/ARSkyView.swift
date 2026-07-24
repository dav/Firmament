import RealityKit
import SwiftUI

struct ARSkyView: UIViewRepresentable {
    let renderer: SkyRenderer

    func makeUIView(context: Context) -> ARView {
        renderer.arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {}
}

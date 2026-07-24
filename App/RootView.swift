import ARKit
import SwiftUI

struct RootView: View {
    /// The simulator can't do world tracking, but it renders the intro tour
    /// (a plain RealityKit scene) fine — letting it through makes the tour
    /// scriptable and screenshot-able without a device.
    private var isSupported: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        ARWorldTrackingConfiguration.isSupported
        #endif
    }

    var body: some View {
        Group {
            if isSupported {
                IntroGateView()
            } else {
                UnsupportedView()
            }
        }
        .task {
            Log.info("ar.capability", ["worldTrackingSupported": ARWorldTrackingConfiguration.isSupported])
        }
    }
}

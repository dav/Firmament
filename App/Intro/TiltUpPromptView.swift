import SwiftUI

/// Shown after the tour while the camera is pointed too low: asks the user to
/// tilt the phone up at the sky. Appears after a short grace period so a user
/// already pointing up never sees it flash.
struct TiltUpPromptView: View {
    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "iphone.gen3.motion")
                .font(.system(size: 44))
                .foregroundStyle(.white)
            Text("Tilt your phone up at the sky")
                .font(.title3.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .opacity(isVisible ? 1 : 0)
        .animation(.easeInOut(duration: 0.5), value: isVisible)
        .task {
            try? await Task.sleep(for: .seconds(0.8))
            isVisible = true
        }
    }
}

import SwiftUI

/// The top overlay row: info button on the left, status HUD centered, settings
/// button on the right.
struct TopBar: View {
    let fix: GeoFix?
    let isDenied: Bool
    @Binding var isShowingSettings: Bool
    @Binding var isShowingInfo: Bool

    var body: some View {
        ZStack(alignment: .top) {
            StatusHUD(fix: fix, isDenied: isDenied)
            GlassEffectContainer(spacing: 16) {
                HStack {
                    Button("About", systemImage: "info.circle") {
                        isShowingInfo = true
                    }
                    Spacer()
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
            }
        }
    }
}

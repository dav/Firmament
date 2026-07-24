import SwiftUI

/// The narration transcript for the current beat, shown in the bottom third of
/// the tour. Cross-fades between beats.
struct TourCaptionView: View {
    let caption: String
    let beatID: BeatID?

    var body: some View {
        ZStack {
            Text(caption)
                .font(.title3)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .id(beatID)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.4), value: beatID)
        .frame(maxWidth: .infinity)
    }
}

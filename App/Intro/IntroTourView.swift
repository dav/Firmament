import SwiftUI

/// The animated tour layer: the tour's RealityKit view plus captions, the skip
/// button, and (in DEBUG builds) the timeline scrubber.
struct IntroTourView: View {
    let director: TourDirector
    let renderer: TourRenderer
    let locationProvider: LocationProvider
    let onSkip: (_ atTime: Double, _ beat: String) -> Void
    let onFinished: () -> Void

    #if DEBUG
    @State private var isShowingScrubber = false
    #endif

    var body: some View {
        ZStack {
            TourSkyView(renderer: renderer)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                #if DEBUG
                HStack {
                    Button("Tuning", systemImage: "wrench.adjustable") {
                        isShowingScrubber.toggle()
                    }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.white.opacity(0.4))
                    Spacer()
                }
                .padding(.horizontal)
                #endif

                Spacer()

                TourCaptionView(
                    caption: director.currentCaption,
                    beatID: director.currentBeatID
                )

                #if DEBUG
                if isShowingScrubber {
                    TourScrubberOverlay(director: director)
                }
                #endif

                VStack(spacing: 10) {
                    TourNextButton {
                        director.skipToNextBeat()
                    }
                    TourSkipButton {
                        onSkip(director.time, director.currentBeatID?.rawValue ?? "unknown")
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .preferredColorScheme(.dark)
        .task {
            // Scene build and playback start are synchronous so the tour can
            // never stall on a black screen; audio probing is the only await
            // and the texture loads in parallel after playback begins.
            let fix = locationProvider.fix
            if fix == nil {
                Log.warn("intro.location.fallback")
            }
            renderer.buildScene(
                homeLatitudeDegrees: fix?.latitudeDegrees ?? 0,
                homeLongitudeDegrees: fix?.longitudeDegrees ?? 0
            )
            await director.load()
            director.onFinished = { onFinished() }
            renderer.startTicking(director: director)
            director.play()
            await renderer.loadEarthTexture()
        }
        .onDisappear {
            renderer.stopTicking()
        }
    }
}

struct TourSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button("Skip", action: action)
            .font(.callout)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.white.opacity(0.1), in: .capsule)
    }
}

/// Hastens to the next beat without ending the tour.
struct TourNextButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Next", systemImage: "forward.end.fill")
                .font(.callout.weight(.medium))
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.white.opacity(0.16), in: .capsule)
    }
}

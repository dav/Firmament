import SwiftUI

/// Hosts the first-launch experience around the main AR screen. Owns the shared
/// app state (settings, location, renderer) so the tour and the live AR view
/// work from the same instances, and mounts the tour layers above `ContentView`
/// while the intro is active.
struct IntroGateView: View {
    @State private var settings: AppSettings
    @State private var locationProvider = LocationProvider()
    @State private var renderer = SkyRenderer()
    @State private var flow: IntroFlowModel
    @State private var tourSession: TourMeldSession?
    @State private var hasStartedLiveSystems = false

    init() {
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        _flow = State(initialValue: IntroFlowModel(settings: settings))
    }

    var body: some View {
        ZStack {
            if flow.phase == .permissions {
                PermissionsPrimerView(
                    locationProvider: locationProvider,
                    onComplete: {
                        startLiveSystemsIfNeeded()
                        flow.permissionsCompleted()
                    },
                    onSkip: {
                        startLiveSystemsIfNeeded()
                        flow.skipTourFromPermissions()
                    }
                )
            } else {
                ContentView(
                    settings: settings,
                    locationProvider: locationProvider,
                    renderer: renderer,
                    flow: flow,
                    onReplayIntro: { flow.replay() }
                )

                if let tourSession, flow.isTourPresented {
                    IntroTourView(
                        director: tourSession.director,
                        renderer: tourSession.renderer,
                        locationProvider: locationProvider,
                        onSkip: { [weak tourSession] time, beat in
                            flow.tourSkipped(atTime: time, beat: beat)
                            tourSession?.meld.skip()
                        },
                        onFinished: { [weak tourSession] in tourSession?.meld.tourDidFinish() }
                    )
                    .transition(.opacity)
                }

                if flow.phase == .holdingForSky {
                    TiltUpPromptView()
                }
            }
        }
        .task {
            flow.logGateDecision()
            if flow.phase == .live {
                startLiveSystemsIfNeeded()
            }
        }
        .onChange(of: flow.phase) { _, phase in
            switch phase {
            case .touring:
                renderer.installFeedOccluder()
                renderer.setDomeHidden(true)
                if tourSession == nil {
                    tourSession = TourMeldSession(flow: flow, skyRenderer: renderer)
                }
            case .live:
                tourSession?.teardown(flow: flow)
                tourSession = nil
                renderer.removeFeedOccluder()
                renderer.setDomeHidden(false)
            case .permissions, .holdingForSky, .revealing:
                break
            }
        }
    }

    private func startLiveSystemsIfNeeded() {
        guard !hasStartedLiveSystems else { return }
        hasStartedLiveSystems = true
        if flow.isIntroActive {
            // Installed before the session's first frame so the camera feed
            // never flashes behind the tour; the dome stays hidden until the
            // intro's reveal fades it in.
            renderer.installFeedOccluder()
            renderer.setDomeHidden(true)
        }
        locationProvider.start()
        renderer.startSession()
    }
}

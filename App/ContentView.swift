import FirmamentCore
import SwiftUI

struct ContentView: View {
    let settings: AppSettings
    let locationProvider: LocationProvider
    let renderer: SkyRenderer
    let flow: IntroFlowModel
    let onReplayIntro: () -> Void

    @State private var isNearRingWindowVisible = true
    @State private var isShowingSettings = false
    @State private var isShowingInfo = false

    // Telemetry throttle state — keeps the 2 Hz render loop from flooding LogRoller.
    @State private var lastSummaryAt: Date?
    @State private var lastLoggedConfig: RenderConfiguration?
    @State private var wasCapped = false
    // Wall-clock of the previous tick, used to animate over the true tick period.
    @State private var lastTickAt: Date?
    private static let summaryInterval: TimeInterval = 10

    var body: some View {
        @Bindable var settings = settings
        return ZStack {
            // Always mounted, even while the opaque tour covers it: RealityKit
            // only renders the tour view's entities while a session-backed
            // ARView is also live in the hierarchy. The feed occluder keeps
            // this view black until the intro's reveal.
            ARSkyView(renderer: renderer)
                .ignoresSafeArea()

            VStack {
                TopBar(
                    fix: locationProvider.fix,
                    isDenied: locationProvider.isDenied,
                    isShowingSettings: $isShowingSettings,
                    isShowingInfo: $isShowingInfo
                )
                ScaleHUD(
                    info: SkyRenderer.scaleInfo(for: settings.renderConfiguration),
                    mode: settings.renderMode,
                    isNearRingWindowVisible: isNearRingWindowVisible
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
                Spacer()
                // The PiP orrery only exists while the chrome is up — during
                // the intro tour its second RealityKit surface must not
                // compete with the tour's own non-AR view.
                if flow.isChromeVisible {
                    OrreryPiP(settings: settings, locationProvider: locationProvider)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.bottom, 10)
                }
                ControlBar(
                    showBelowHorizon: $settings.showBelowHorizon,
                    renderMode: $settings.renderMode
                )
            }
            .padding()
            .opacity(flow.isChromeVisible ? 1 : 0)
            .allowsHitTesting(flow.isChromeVisible)
            .animation(.easeIn(duration: 0.5), value: flow.isChromeVisible)
        }
        .onChange(of: settings.renderMode) { _, mode in
            Log.info("ui.renderMode.toggle", ["mode": mode.rawValue])
            Task { await refreshSky() }
        }
        .onChange(of: settings.showBelowHorizon) { _, isOn in
            Log.info("ui.belowHorizon.toggle", ["on": isOn])
            Task { await refreshSky() }
        }
        .onChange(of: isShowingSettings) { _, isOpen in
            if isOpen { Log.info("ui.settings.open") }
        }
        .onChange(of: isShowingInfo) { _, isOpen in
            if isOpen { Log.info("ui.info.open") }
        }
        .task {
            while !Task.isCancelled {
                // While the tour plays there's nothing to render live — skip
                // the astronomy tick entirely; it resumes at the meld, and one
                // tick fully repopulates the dome.
                if flow.isLiveDomeActive {
                    await refreshSky()
                }
                try? await Task.sleep(for: .seconds(SkyRenderer.updateInterval))
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(settings: settings, onReplayIntro: onReplayIntro)
        }
        .sheet(isPresented: $isShowingInfo) {
            InfoView()
        }
    }

    private func refreshSky() async {
        guard let fix = effectiveFix() else { return }
        let now = Date.now
        let observer = ObserverState(
            date: now,
            latitudeDegrees: fix.latitudeDegrees,
            longitudeDegrees: fix.longitudeDegrees,
            altitudeMeters: fix.altitudeMeters
        )
        let futureObserver = ObserverState(
            date: now.addingTimeInterval(SkyRenderer.updateInterval),
            latitudeDegrees: fix.latitudeDegrees,
            longitudeDegrees: fix.longitudeDegrees,
            altitudeMeters: fix.altitudeMeters
        )
        let config = settings.renderConfiguration

        // Heavy astronomy/geometry runs off the main actor so it never stalls the
        // render loop; only the entity mutation below touches RealityKit.
        let computeStart = Date.now
        let frame = await Task.detached(priority: .userInitiated) {
            SkyRenderer.computeFrame(observer: observer, futureObserver: futureObserver, configuration: config)
        }.value
        let computeMs = Date.now.timeIntervalSince(computeStart) * 1_000

        // Animate over the true tick period so cubes glide continuously into the
        // next update instead of arriving early and holding (the old stutter).
        // The gap is capped near a normal tick: after the loop stalls (a sheet
        // was open, the app was idle), `lastTickAt` is stale, and without the
        // cap a mode change or fix update would crawl the whole dome over
        // seconds — which reads as the toggle being "slow to react."
        let period = lastTickAt.map { now.timeIntervalSince($0) } ?? SkyRenderer.updateInterval
        lastTickAt = now
        let animationDuration = min(max(period, 0.15), SkyRenderer.updateInterval * 2)

        let renderStart = Date.now
        renderer.render(frame, faceColors: config.faceColors, animationDuration: animationDuration)
        // During the intro handoff the meld watches these frames for the
        // "any nodes above the horizon" reveal gate.
        flow.liveFrameHandler?(frame, config.faceColors, animationDuration)
        let renderMs = Date.now.timeIntervalSince(renderStart) * 1_000

        isNearRingWindowVisible = frame.stats.isNearRingWindowVisible
        logTelemetry(
            stats: frame.stats,
            observer: observer,
            config: config,
            timing: TickTiming(computeMs: computeMs, renderMs: renderMs, periodMs: period * 1_000)
        )
    }

    /// The real fix when we have one. During the intro a missing or denied fix
    /// falls back to a fixed coordinate so the live dome isn't empty at the
    /// tour handoff — both scenes must render the same sky either way.
    private func effectiveFix() -> GeoFix? {
        if let fix = locationProvider.fix { return fix }
        guard flow.isIntroActive else { return nil }
        return GeoFix(
            latitudeDegrees: 0,
            longitudeDegrees: 0,
            altitudeMeters: 0,
            horizontalAccuracyMeters: -1,
            timestamp: .now
        )
    }

    private struct TickTiming {
        let computeMs: Double
        let renderMs: Double
        let periodMs: Double
    }

    /// Emits render telemetry sparingly: a heartbeat summary at most every
    /// `summaryInterval` seconds, plus event-driven config-change and node-cap
    /// transition logs. No per-tick or per-node events.
    private func logTelemetry(
        stats: RenderStats,
        observer: ObserverState,
        config: RenderConfiguration,
        timing: TickTiming
    ) {
        if lastLoggedConfig != config {
            lastLoggedConfig = config
            Log.info("render.config", [
                "mode": config.renderMode.rawValue,
                "unit_spacing_km": config.unitSpacingKm,
                "in_plane_radius_km": config.inPlaneRadiusKm,
                "out_of_plane_half_extent_km": config.outOfPlaneHalfExtentKm,
                "tube_radius_km": config.tubeRadiusKm,
                "tube_nodes_per_ring": config.sanitizedNodesPerRing,
                "tube_cube_edge_km": config.tubeCubeEdgeKm,
                "cube_edge_km": config.cubeEdgeKm,
                "ghost_band_deg": config.ghostBandDegrees,
                "show_ghosts": config.showGhostNodes,
                "show_below_horizon": config.showBelowHorizon
            ])
        }

        if stats.didCapNodes != wasCapped {
            wasCapped = stats.didCapNodes
            Log.warn("render.nodesCapped", ["capped": stats.didCapNodes, "placed": stats.placedCount])
        }

        let now = Date.now
        if let last = lastSummaryAt, now.timeIntervalSince(last) < Self.summaryInterval {
            return
        }
        lastSummaryAt = now
        let heliocentricAU = observer.heliocentricPositionKm.length / Astronomy.astronomicalUnitKm
        Log.debug("render.summary", [
            "above_horizon": stats.aboveHorizonCount,
            "placed": stats.placedCount,
            "nearest_km": stats.nearestKm,
            "farthest_km": stats.farthestKm,
            "heliocentric_au": heliocentricAU,
            "sun_az_deg": stats.sunAzimuthDegrees,
            "sun_el_deg": stats.sunElevationDegrees,
            "sun_above_horizon": stats.sunAboveHorizon,
            "lat": observer.latitudeDegrees,
            "lon": observer.longitudeDegrees,
            // Perf timing folded in so before/after is visible without a new stream.
            "compute_ms": timing.computeMs,
            "render_ms": timing.renderMs,
            "period_ms": timing.periodMs
        ])
    }
}

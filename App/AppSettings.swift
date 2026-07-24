import FirmamentCore
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let defaultGhostBandDegrees = 5.0

    // Locked render tuning — the dialed-in experience. These were user
    // sliders once (see git history); the values below were chosen on-device
    // and frozen so the app always renders the intended look.
    /// Distance between neighboring markers — and between tube/ride rings.
    static let unitSpacingKm = 100.0
    /// Grid reach within the orbital plane, in Earth diameters.
    static let inPlaneReachDiameters = 6.0
    /// Grid reach above/below the orbital plane, in Earth diameters.
    static let outOfPlaneReachDiameters = 3.0
    /// Diameter of the tube-mode orbit tube, in Earth diameters — Earth
    /// floats well inside it.
    static let tubeDiameterDiameters = 1.0
    /// Ride mode: distance from the observer to the tube wall, km. The tube
    /// is threaded through the observer, so rings always arch right overhead.
    static let rideWallDistanceKm = 100.0
    /// Nodes per tube ring (tube and ride); even, so two always sit on the
    /// ring's midline.
    static let tubeNodesPerRing = 16
    /// Cube edge in tube mode, km.
    static let tubeCubeEdgeKm = 30.0
    /// Cube edge in ride mode, km.
    static let rideCubeEdgeKm = 10.0
    /// Cube edge in grid mode, km.
    static let cubeEdgeKm = 10.0

    var renderMode: RenderMode { didSet { persist() } }
    var ghostBandDegrees: Double { didSet { persist() } }
    var showGhostNodes: Bool { didSet { persist() } }
    /// X-ray mode: render everything below the horizon as ghosts instead of
    /// letting the Earth occlude it.
    var showBelowHorizon: Bool { didSet { persist() } }
    var faceColors: [Color.Resolved] { didSet { persist() } }
    /// Whether the picture-in-picture orrery window is expanded. UI state,
    /// like `hasSeenIntro`, so `resetToDefaults()` leaves it alone.
    var isOrreryExpanded: Bool { didSet { persist() } }
    /// Whether the first-launch intro tour has been completed or skipped.
    /// Deliberately untouched by `resetToDefaults()` — that resets render tuning,
    /// not app lifecycle state.
    var hasSeenIntro: Bool { didSet { persist() } }
    #if DEBUG
    /// Development aid: run the intro tour on every launch regardless of
    /// `hasSeenIntro`.
    var debugAlwaysShowIntro: Bool { didSet { persist() } }
    #endif

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        renderMode = RenderMode(rawValue: defaults.string(forKey: Keys.renderMode) ?? "") ?? .grid
        ghostBandDegrees = defaults.object(forKey: Keys.ghostBand) as? Double ?? Self.defaultGhostBandDegrees
        showGhostNodes = defaults.object(forKey: Keys.showGhosts) as? Bool ?? true
        showBelowHorizon = defaults.object(forKey: Keys.showBelowHorizon) as? Bool ?? false
        faceColors = Self.loadFaceColors(from: defaults)
        isOrreryExpanded = defaults.object(forKey: Keys.orreryExpanded) as? Bool ?? true
        hasSeenIntro = defaults.object(forKey: Keys.hasSeenIntro) as? Bool ?? false
        #if DEBUG
        debugAlwaysShowIntro = defaults.object(forKey: Keys.debugAlwaysShowIntro) as? Bool ?? false
        #endif
    }

    var renderConfiguration: RenderConfiguration {
        RenderConfiguration(
            renderMode: renderMode,
            unitSpacingKm: Self.unitSpacingKm,
            inPlaneRadiusKm: Self.inPlaneReachDiameters * Geodesy.meanDiameterKm,
            outOfPlaneHalfExtentKm: Self.outOfPlaneReachDiameters * Geodesy.meanDiameterKm,
            tubeRadiusKm: renderMode == .ride
                ? Self.rideWallDistanceKm
                : Self.tubeDiameterDiameters * Geodesy.meanDiameterKm / 2,
            tubeNodesPerRing: Self.tubeNodesPerRing,
            cubeEdgeKm: Self.cubeEdgeKm,
            tubeCubeEdgeKm: renderMode == .ride ? Self.rideCubeEdgeKm : Self.tubeCubeEdgeKm,
            ghostBandDegrees: ghostBandDegrees,
            showGhostNodes: showGhostNodes,
            showBelowHorizon: showBelowHorizon,
            faceColors: faceColors
        )
    }

    func resetToDefaults() {
        renderMode = .grid
        ghostBandDegrees = Self.defaultGhostBandDegrees
        showGhostNodes = true
        showBelowHorizon = false
        faceColors = CubeFace.defaultColors
    }

    private func persist() {
        defaults.set(renderMode.rawValue, forKey: Keys.renderMode)
        defaults.set(ghostBandDegrees, forKey: Keys.ghostBand)
        defaults.set(showGhostNodes, forKey: Keys.showGhosts)
        defaults.set(showBelowHorizon, forKey: Keys.showBelowHorizon)
        if let data = try? JSONEncoder().encode(faceColors) {
            defaults.set(data, forKey: Keys.faceColors)
        }
        defaults.set(isOrreryExpanded, forKey: Keys.orreryExpanded)
        defaults.set(hasSeenIntro, forKey: Keys.hasSeenIntro)
        #if DEBUG
        defaults.set(debugAlwaysShowIntro, forKey: Keys.debugAlwaysShowIntro)
        #endif
    }

    private static func loadFaceColors(from defaults: UserDefaults) -> [Color.Resolved] {
        guard
            let data = defaults.data(forKey: Keys.faceColors),
            let colors = try? JSONDecoder().decode([Color.Resolved].self, from: data),
            colors.count == CubeFace.allCases.count
        else {
            return CubeFace.defaultColors
        }
        return colors
    }

    private enum Keys {
        static let renderMode = "settings.renderMode"
        static let ghostBand = "settings.ghostBandDegrees"
        static let showGhosts = "settings.showGhostNodes"
        static let showBelowHorizon = "settings.showBelowHorizon"
        static let faceColors = "settings.faceColors"
        static let orreryExpanded = "settings.orreryExpanded"
        static let hasSeenIntro = "settings.hasSeenIntro"
        static let debugAlwaysShowIntro = "settings.debug.alwaysShowIntro"
    }
}

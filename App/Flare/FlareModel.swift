import FirmamentCore
import Foundation
import SwiftUI
import simd

/// All the state behind the flare button: the marker itself, how far the user
/// has travelled from it, and the aim guide that gets them pointed at it.
///
/// The guide exists because the drop point is never where the phone happens to
/// be looking — it is fixed by Earth's direction of travel, not by the user — so
/// dropping blind means watching nothing at all.
@MainActor
@Observable
final class FlareModel {
    /// The marker, once dropped. Its heliocentric point never moves again.
    private(set) var dropped: DroppedFlare?
    /// Distance from the observer as of the last tick; survives the flare going
    /// behind the Earth, so the chrome can keep counting when the sky is empty.
    private(set) var distanceKm: Double?
    /// Where a flare dropped right now would fall to. Refreshed every astronomy
    /// tick — it drifts 15°/hour as the Earth turns under the observer.
    private(set) var target = FlareDropTarget.unknown

    private(set) var isGuiding = false
    private(set) var aim: FlareAim?
    /// `FlareAim.isOnTarget` carried across samples, with hysteresis.
    private(set) var isOnTarget = false

    /// Set when the flare experience switched Earth occlusion off itself, so it
    /// knows to hand the user's own setting back once the flare is done with.
    private var didDisableOcclusion = false

    var isDropped: Bool { dropped != nil }

    init(target: FlareDropTarget = .unknown) {
        self.target = target
    }

    /// Picks up the flare's distance and the live drop target from each frame.
    func apply(_ frame: SkyFrame) {
        distanceKm = frame.flare?.distanceKm
        target = frame.flareDropTarget
    }

    /// The flare button's whole behavior: remove what's out, drop when the
    /// camera is already pointed at the spot, and otherwise raise the guide.
    func toggle(fix: GeoFix, cameraForward: SIMD3<Float>, showBelowHorizon: Binding<Bool>) {
        guard dropped == nil else {
            dropped = nil
            distanceKm = nil
            stopGuiding()
            restoreOcclusion(showBelowHorizon)
            Log.info("ui.flare.remove")
            return
        }
        guard isReadyToDrop(
            cameraForward: cameraForward,
            showBelowHorizon: showBelowHorizon.wrappedValue
        ) else {
            beginGuiding(cameraForward: cameraForward, showBelowHorizon: showBelowHorizon)
            Log.info("ui.flare.aimGuide.begin", [
                "offset_deg": aim.map { $0.offsetRadians * 180 / .pi },
                "target_el_deg": target.elevationRadians * 180 / .pi
            ])
            return
        }
        // Deliberately no `restoreOcclusion` here: the flare is about to be out
        // and watched, and it lives below the horizon for as long as its path
        // does. The setting goes back when the flare does.
        stopGuiding()

        let now = Date.now
        let observer = ObserverState(
            date: now,
            latitudeDegrees: fix.latitudeDegrees,
            longitudeDegrees: fix.longitudeDegrees,
            altitudeMeters: fix.altitudeMeters
        )
        dropped = DroppedFlare(heliocentricKm: observer.heliocentricPositionKm, droppedAt: now)
        Log.info("ui.flare.drop", [
            "lat": fix.latitudeDegrees,
            "lon": fix.longitudeDegrees,
            "diameter_km": DroppedFlare.diameterKm
        ])
    }

    func cancelAim(showBelowHorizon: Binding<Bool>) {
        stopGuiding()
        restoreOcclusion(showBelowHorizon)
        Log.info("ui.flare.aimGuide.cancel")
    }

    /// Whether a flare dropped this instant would actually be watchable: on
    /// screen, and not swallowed by the Earth.
    func isReadyToDrop(cameraForward: SIMD3<Float>, showBelowHorizon: Bool) -> Bool {
        let aim = FlareAim(target: target, cameraForward: cameraForward)
        return aim.isOnTarget && !aim.needsXRay(showBelowHorizon: showBelowHorizon)
    }

    /// While the guide is up the button follows the tracked (hysteretic) verdict,
    /// so it doesn't disarm the instant a hand wobbles.
    func isArmed(showBelowHorizon: Bool) -> Bool {
        guard let aim else { return false }
        return isOnTarget && !aim.needsXRay(showBelowHorizon: showBelowHorizon)
    }

    /// Raises the guide, clearing the Earth out of the way first when the drop
    /// point is under the horizon. Watching the grid recede through the ground
    /// is *how* you find the direction, so occlusion is switched off outright
    /// rather than offered — asking would gate the aiming on the very thing the
    /// aiming needs.
    func beginGuiding(cameraForward: SIMD3<Float>, showBelowHorizon: Binding<Bool>) {
        isGuiding = true
        isOnTarget = false
        if target.elevationRadians < 0, !showBelowHorizon.wrappedValue {
            showBelowHorizon.wrappedValue = true
            didDisableOcclusion = true
            Log.info("ui.flare.occlusion.autoDisabled", [
                "target_el_deg": target.elevationRadians * 180 / .pi
            ])
        }
        track(cameraForward: cameraForward)
    }

    func stopGuiding() {
        isGuiding = false
        aim = nil
        isOnTarget = false
    }

    /// Hands the occlusion setting back once the flare experience is over —
    /// but only if we were the ones who changed it, and only if the user hasn't
    /// since turned occlusion back on themselves.
    private func restoreOcclusion(_ showBelowHorizon: Binding<Bool>) {
        guard didDisableOcclusion else { return }
        didDisableOcclusion = false
        guard showBelowHorizon.wrappedValue else { return }
        showBelowHorizon.wrappedValue = false
        Log.info("ui.flare.occlusion.restored")
    }

    /// One sample of the live camera pose. Called fast (tens of hertz) while the
    /// guide is up so the readout keeps pace with the user's hands.
    func track(cameraForward: SIMD3<Float>) {
        let aim = FlareAim(target: target, cameraForward: cameraForward)
        self.aim = aim
        isOnTarget = isOnTarget
            ? aim.offsetRadians <= FlareAim.offTargetRadians
            : aim.offsetRadians <= FlareAim.onTargetRadians
    }
}

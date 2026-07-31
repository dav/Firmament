import Foundation
import SwiftUI
import Testing
@testable import Firmament

/// AR world frame under `.gravityAndHeading`: +x east, +y up, +z south.
private func forward(azimuthDegrees: Double, elevationDegrees: Double) -> SIMD3<Float> {
    let azimuth = azimuthDegrees * .pi / 180
    let elevation = elevationDegrees * .pi / 180
    let cosElevation = cos(elevation)
    return SIMD3(
        Float(sin(azimuth) * cosElevation),
        Float(sin(elevation)),
        Float(-cos(azimuth) * cosElevation)
    )
}

private func target(azimuthDegrees: Double, elevationDegrees: Double) -> FlareDropTarget {
    FlareDropTarget(
        azimuthRadians: azimuthDegrees * .pi / 180,
        elevationRadians: elevationDegrees * .pi / 180
    )
}

private func degrees(_ radians: Double) -> Double { radians * 180 / .pi }

@Test func aimAtTheTargetIsZeroOffset() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 137, elevationDegrees: 22),
        cameraForward: forward(azimuthDegrees: 137, elevationDegrees: 22)
    )

    #expect(abs(degrees(aim.offsetRadians)) < 0.01)
    #expect(abs(degrees(aim.yawRadians)) < 0.01)
    #expect(abs(degrees(aim.pitchRadians)) < 0.01)
    #expect(aim.isOnTarget)
    #expect(aim.instructions.isEmpty)
}

@Test func targetToTheEastOfNorthTurnsRight() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 90, elevationDegrees: 0),
        cameraForward: forward(azimuthDegrees: 0, elevationDegrees: 0)
    )

    #expect(abs(degrees(aim.yawRadians) - 90) < 0.01)
    #expect(aim.instructions.first?.text == "Turn right 90°")
}

@Test func targetToTheWestOfNorthTurnsLeft() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 280, elevationDegrees: 0),
        cameraForward: forward(azimuthDegrees: 0, elevationDegrees: 0)
    )

    #expect(abs(degrees(aim.yawRadians) + 80) < 0.01)
    #expect(aim.instructions.first?.text == "Turn left 80°")
}

/// The short way round: 350° of "turn right" must read as 10° of "turn left".
@Test func yawTakesTheShortWayAroundNorth() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 350, elevationDegrees: 0),
        cameraForward: forward(azimuthDegrees: 0, elevationDegrees: 0)
    )

    #expect(abs(degrees(aim.yawRadians) + 10) < 0.01)
    #expect(aim.instructions.first?.text == "Turn left 10°")
}

@Test func higherTargetTiltsUp() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 45, elevationDegrees: 30),
        cameraForward: forward(azimuthDegrees: 45, elevationDegrees: -5)
    )

    #expect(abs(degrees(aim.pitchRadians) - 35) < 0.01)
    #expect(aim.instructions.map(\.text) == ["Tilt up 35°"])
}

@Test func lowerTargetTiltsDown() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 45, elevationDegrees: -20),
        cameraForward: forward(azimuthDegrees: 45, elevationDegrees: 10)
    )

    #expect(abs(degrees(aim.pitchRadians) + 30) < 0.01)
    #expect(aim.instructions.map(\.text) == ["Tilt down 30°"])
}

@Test func bothAxesAreReportedTurnFirst() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 60, elevationDegrees: 25),
        cameraForward: forward(azimuthDegrees: 20, elevationDegrees: 0)
    )

    #expect(aim.instructions.map(\.systemImage) == ["arrow.turn.up.right", "arrow.up"])
}

/// Corrections under the noise floor aren't worth a line of guidance.
@Test func tinyCorrectionsProduceNoInstructions() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 45, elevationDegrees: 10),
        cameraForward: forward(azimuthDegrees: 46, elevationDegrees: 11)
    )

    #expect(aim.instructions.isEmpty)
    #expect(aim.isOnTarget)
}

@Test func offsetIsGreatCircleNotTheSumOfAxes() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 0, elevationDegrees: 80),
        cameraForward: forward(azimuthDegrees: 180, elevationDegrees: 80)
    )

    // Two points 10° from the zenith on opposite meridians are 20° apart, even
    // though the azimuths differ by 180°.
    #expect(abs(degrees(aim.offsetRadians) - 20) < 0.01)
    #expect(!aim.isOnTarget)
}

@Test func offTargetJustPastTheTolerance() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 20, elevationDegrees: 0),
        cameraForward: forward(azimuthDegrees: 0, elevationDegrees: 0)
    )

    #expect(!aim.isOnTarget)
    #expect(degrees(aim.offsetRadians) > degrees(FlareAim.onTargetRadians))
}

@Test func belowHorizonTargetNeedsXRayOnlyWhileOcclusionIsOn() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 45, elevationDegrees: -25),
        cameraForward: forward(azimuthDegrees: 45, elevationDegrees: -25)
    )

    #expect(aim.isBelowHorizon)
    #expect(aim.needsXRay(showBelowHorizon: false))
    #expect(!aim.needsXRay(showBelowHorizon: true))
}

@Test func aboveHorizonTargetNeverNeedsXRay() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 45, elevationDegrees: 5),
        cameraForward: forward(azimuthDegrees: 45, elevationDegrees: 5)
    )

    #expect(!aim.isBelowHorizon)
    #expect(!aim.needsXRay(showBelowHorizon: false))
}

@Test func aDegenerateCameraVectorFallsBackToNorth() {
    let aim = FlareAim(
        target: target(azimuthDegrees: 0, elevationDegrees: 0),
        cameraForward: .zero
    )

    #expect(abs(degrees(aim.offsetRadians)) < 0.01)
}

/// A stand-in for the app's Earth-occlusion setting.
@MainActor
private final class OcclusionSetting {
    var showBelowHorizon: Bool

    init(showBelowHorizon: Bool) {
        self.showBelowHorizon = showBelowHorizon
    }

    var binding: Binding<Bool> {
        Binding(get: { self.showBelowHorizon }, set: { self.showBelowHorizon = $0 })
    }
}

// MARK: - Arming

@MainActor
@Test func armingIsBlockedUntilTheCameraComesRound() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: 20))

    #expect(!model.isReadyToDrop(
        cameraForward: forward(azimuthDegrees: 270, elevationDegrees: 20),
        showBelowHorizon: false
    ))
    #expect(model.isReadyToDrop(
        cameraForward: forward(azimuthDegrees: 95, elevationDegrees: 22),
        showBelowHorizon: false
    ))
}

@MainActor
@Test func armingIsBlockedByOcclusionWhenTheDropPointIsUnderTheHorizon() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: -30))
    let aimed = forward(azimuthDegrees: 90, elevationDegrees: -30)

    #expect(!model.isReadyToDrop(cameraForward: aimed, showBelowHorizon: false))
    #expect(model.isReadyToDrop(cameraForward: aimed, showBelowHorizon: true))
}

/// Hysteresis: crossing in at 15° but only falling back out past 20°, so a
/// shaky hand on the boundary can't strobe the button.
@MainActor
@Test func trackingHoldsOnTargetThroughSmallDrift() {
    let model = FlareModel(target: target(azimuthDegrees: 0, elevationDegrees: 0))

    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 5, elevationDegrees: 0),
        showBelowHorizon: OcclusionSetting(showBelowHorizon: false).binding
    )
    #expect(model.isOnTarget)

    model.track(cameraForward: forward(azimuthDegrees: 18, elevationDegrees: 0))
    #expect(model.isOnTarget)

    model.track(cameraForward: forward(azimuthDegrees: 25, elevationDegrees: 0))
    #expect(!model.isOnTarget)

    // And back in again only once it is inside the tighter bound.
    model.track(cameraForward: forward(azimuthDegrees: 18, elevationDegrees: 0))
    #expect(!model.isOnTarget)
    model.track(cameraForward: forward(azimuthDegrees: 12, elevationDegrees: 0))
    #expect(model.isOnTarget)
}

// MARK: - Earth occlusion

/// Finding the direction means watching the grid recede into it, so an occluded
/// drop point clears the Earth rather than asking the user to.
@MainActor
@Test func guidingAnOccludedDropPointTurnsOcclusionOff() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: -30))
    let occlusion = OcclusionSetting(showBelowHorizon: false)

    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 270, elevationDegrees: 0),
        showBelowHorizon: occlusion.binding
    )

    #expect(occlusion.showBelowHorizon)
    #expect(model.isArmed(showBelowHorizon: occlusion.showBelowHorizon) == model.isOnTarget)
}

@MainActor
@Test func guidingAnUnoccludedDropPointLeavesTheSettingAlone() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: 30))
    let occlusion = OcclusionSetting(showBelowHorizon: false)

    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 270, elevationDegrees: 0),
        showBelowHorizon: occlusion.binding
    )

    #expect(!occlusion.showBelowHorizon)
}

@MainActor
@Test func cancellingTheGuideHandsTheOcclusionSettingBack() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: -30))
    let occlusion = OcclusionSetting(showBelowHorizon: false)

    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 270, elevationDegrees: 0),
        showBelowHorizon: occlusion.binding
    )
    model.cancelAim(showBelowHorizon: occlusion.binding)

    #expect(!occlusion.showBelowHorizon)
}

/// A setting the user already had off is theirs, not ours to put back.
@MainActor
@Test func cancellingDoesNotTouchAnOcclusionSettingWeDidNotChange() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: -30))
    let occlusion = OcclusionSetting(showBelowHorizon: true)

    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 270, elevationDegrees: 0),
        showBelowHorizon: occlusion.binding
    )
    model.cancelAim(showBelowHorizon: occlusion.binding)

    #expect(occlusion.showBelowHorizon)
}

/// Turning occlusion back on mid-aim is a decision; cancelling must not undo it
/// a second time.
@MainActor
@Test func aUserReenablingOcclusionMidAimSticks() {
    let model = FlareModel(target: target(azimuthDegrees: 90, elevationDegrees: -30))
    let occlusion = OcclusionSetting(showBelowHorizon: false)

    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 270, elevationDegrees: 0),
        showBelowHorizon: occlusion.binding
    )
    occlusion.showBelowHorizon = false
    model.cancelAim(showBelowHorizon: occlusion.binding)

    #expect(!occlusion.showBelowHorizon)
}

@MainActor
@Test func stoppingTheGuideClearsItsState() {
    let model = FlareModel(target: target(azimuthDegrees: 0, elevationDegrees: 0))
    model.beginGuiding(
        cameraForward: forward(azimuthDegrees: 0, elevationDegrees: 0),
        showBelowHorizon: OcclusionSetting(showBelowHorizon: false).binding
    )

    #expect(model.isGuiding)
    #expect(model.isArmed(showBelowHorizon: false))

    model.stopGuiding()
    #expect(!model.isGuiding)
    #expect(model.aim == nil)
    #expect(!model.isArmed(showBelowHorizon: false))
}

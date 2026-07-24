import Foundation
import Testing
@testable import FirmamentCore

/// End-to-end pipeline tests. The Sun sits at lattice node (0,0,0), so its computed
/// azimuth/elevation can be checked against JPL Horizons ephemerides (airless apparent,
/// QUANTITIES=4). Horizons values include aberration/nutation/light-time (~arcseconds);
/// the model is geometric, so the tolerance is 2 arcminutes — within the arcminute-class
/// accuracy target.
struct IntegrationTests {
    private let arcminutes2 = 2.0 / 60.0 * Double.pi / 180

    @Test func sunPositionSanFrancisco() {
        // JPL Horizons: Sun from (-122.4194, 37.7749, 50 m), 2026-06-20 20:00:00 UTC:
        // azimuth 169.578968°, elevation 75.457252°.
        let observer = ObserverState(
            date: utcDate(2026, 6, 20, 20, 0, 0),
            latitudeDegrees: 37.7749,
            longitudeDegrees: -122.4194,
            altitudeMeters: 50
        )
        let sun = Firmament.skyPosition(of: LatticeNode(i: 0, j: 0, k: 0), observer: observer, unitSpacingKm: 3_185)
        #expect(abs(sun.azimuthRadians - 169.578_968 * .pi / 180) < arcminutes2)
        #expect(abs(sun.elevationRadians - 75.457_252 * .pi / 180) < arcminutes2)
    }

    @Test func sunPositionSydney() {
        // JPL Horizons: Sun from (151.2093, -33.8688, 20 m), 2026-01-15 06:00:00 UTC:
        // azimuth 267.816590°, elevation 36.942415°.
        let observer = ObserverState(
            date: utcDate(2026, 1, 15, 6, 0, 0),
            latitudeDegrees: -33.8688,
            longitudeDegrees: 151.2093,
            altitudeMeters: 20
        )
        let sun = Firmament.skyPosition(of: LatticeNode(i: 0, j: 0, k: 0), observer: observer, unitSpacingKm: 3_185)
        #expect(abs(sun.azimuthRadians - 267.816_590 * .pi / 180) < arcminutes2)
        #expect(abs(sun.elevationRadians - 36.942_415 * .pi / 180) < arcminutes2)
    }

    @Test func sunDistanceIsOneAU() {
        let observer = ObserverState(
            date: utcDate(2026, 1, 15, 6, 0, 0),
            latitudeDegrees: -33.8688,
            longitudeDegrees: 151.2093,
            altitudeMeters: 20
        )
        let sun = Firmament.skyPosition(of: LatticeNode(i: 0, j: 0, k: 0), observer: observer, unitSpacingKm: 3_185)
        let distanceAU = sun.distanceKm / Astronomy.astronomicalUnitKm
        #expect(distanceAU > 0.98 && distanceAU < 0.987) // Earth is near perihelion in mid-January
    }

    @Test func pointStraightUpHasNinetyDegreeElevation() {
        let observer = ObserverState(
            date: utcDate(2026, 3, 1, 12, 0, 0),
            latitudeDegrees: 51.4778,
            longitudeDegrees: 0,
            altitudeMeters: 0
        )
        let upEcef = Frames.enuInverseUp(
            latitudeRadians: observer.latitudeRadians,
            longitudeRadians: observer.longitudeRadians
        )
        let upEcliptic = Frames.eclipticFromEcef(
            upEcef,
            gmstRadians: observer.gmstRadians,
            obliquityRadians: observer.obliquityRadians
        )
        let point = observer.heliocentricPositionKm + upEcliptic * 5_000
        let direction = Firmament.skyDirection(toHeliocentricKm: point, observer: observer)
        #expect(abs(direction.elevationRadians - .pi / 2) < 1e-6)
        #expect(abs(direction.distanceKm - 5_000) < 1e-6)
    }

    @Test func visibleNodesAreAboveHorizonAndSorted() {
        let observer = ObserverState(
            date: utcDate(2026, 6, 20, 20, 0, 0),
            latitudeDegrees: 37.7749,
            longitudeDegrees: -122.4194,
            altitudeMeters: 50
        )
        let visible = Firmament.visibleNodes(
            observer: observer,
            unitSpacingKm: 3_185,
            inPlaneRadiusKm: 20_000,
            outOfPlaneHalfExtentKm: 20_000
        )
        #expect(!visible.isEmpty)
        for position in visible {
            #expect(position.elevationRadians >= 0)
            #expect(position.distanceKm <= 20_000 * 2.0.squareRoot() + 1)
        }
        for index in 1..<visible.count {
            #expect(visible[index - 1].distanceKm <= visible[index].distanceKm)
        }
    }

    @Test func ghostBandIncludesJustBelowHorizon() {
        let observer = ObserverState(
            date: utcDate(2026, 6, 20, 20, 0, 0),
            latitudeDegrees: 37.7749,
            longitudeDegrees: -122.4194,
            altitudeMeters: 50
        )
        let ghostBand = -5.0 * Double.pi / 180
        let withGhosts = Firmament.visibleNodes(
            observer: observer,
            unitSpacingKm: 3_185,
            inPlaneRadiusKm: 20_000,
            outOfPlaneHalfExtentKm: 20_000,
            minElevationRadians: ghostBand
        )
        let strictlyVisible = Firmament.visibleNodes(
            observer: observer,
            unitSpacingKm: 3_185,
            inPlaneRadiusKm: 20_000,
            outOfPlaneHalfExtentKm: 20_000
        )
        #expect(withGhosts.count >= strictlyVisible.count)
        for position in withGhosts {
            #expect(position.elevationRadians >= ghostBand)
        }
    }
}

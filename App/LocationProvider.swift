import CoreLocation
import Observation

@MainActor
@Observable
final class LocationProvider {
    private(set) var fix: GeoFix?
    private(set) var isDenied = false
    /// True once the location authorization prompt has been answered (either
    /// way) — the first-launch flow waits on this before starting the tour.
    private(set) var authorizationResolved = false

    private var updatesTask: Task<Void, Never>?

    func start() {
        guard updatesTask == nil else { return }
        Log.info("location.start")
        updatesTask = Task {
            do {
                for try await update in CLLocationUpdate.liveUpdates() {
                    updateDeniedState(update.authorizationDenied)
                    if !update.authorizationRequestInProgress {
                        authorizationResolved = true
                    }
                    if let location = update.location {
                        let hadFix = fix != nil
                        fix = GeoFix(
                            latitudeDegrees: location.coordinate.latitude,
                            longitudeDegrees: location.coordinate.longitude,
                            altitudeMeters: location.altitude,
                            horizontalAccuracyMeters: location.horizontalAccuracy,
                            timestamp: location.timestamp
                        )
                        // Only the first fix is logged here; ongoing fixes (~1 Hz) are
                        // sampled by the throttled render summary instead.
                        if !hadFix {
                            Log.info("location.firstFix", [
                                "lat": location.coordinate.latitude,
                                "lon": location.coordinate.longitude,
                                "altitude_m": location.altitude,
                                "accuracy_m": location.horizontalAccuracy
                            ])
                        }
                    }
                }
            } catch {
                authorizationResolved = true
                updateDeniedState(true)
                Log.error("location.updatesFailed", ["error": String(describing: error)])
            }
        }
    }

    private func updateDeniedState(_ denied: Bool) {
        guard denied != isDenied else { return }
        isDenied = denied
        if denied {
            Log.warn("location.denied")
        } else {
            Log.info("location.authorized")
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }
}

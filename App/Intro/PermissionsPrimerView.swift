import AVFoundation
import CoreLocation
import SwiftUI

/// Black full-screen primer shown before the tour. Requests camera and location
/// access up front so the tour plays uninterrupted, the final beat can target
/// the device's real coordinates, and the AR session can warm up invisibly.
struct PermissionsPrimerView: View {
    let locationProvider: LocationProvider
    let onComplete: () -> Void
    let onSkip: () -> Void

    @State private var isRequesting = false

    /// If the location prompt is never answered (or updates stall), proceed
    /// anyway — the tour falls back to default coordinates.
    private static let locationResolutionTimeout: TimeInterval = 10

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 24) {
                Spacer()
                Image("FirmamentTitle")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 340)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                    .accessibilityLabel("Dav's Celestial Firmament")
                Text(primerText)
                .font(.body)
                .foregroundStyle(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                Spacer()
                VStack(spacing: 16) {
                    Button {
                        beginRequests(then: onComplete)
                    } label: {
                        if isRequesting {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text("Begin")
                                .font(.title3.bold())
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(.black)
                    .disabled(isRequesting)

                    Button("Skip tour") {
                        beginRequests(then: onSkip)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
                    .disabled(isRequesting)
                }
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        #if targetEnvironment(simulator)
        // No one can tap Begin in an automated simulator run.
        .task {
            try? await Task.sleep(for: .seconds(0.3))
            beginRequests(then: onComplete)
        }
        #endif
    }

    /// Skip the access explanation when the system already granted everything
    /// (replays, DEBUG always-show launches) — no point announcing a request
    /// that will never appear.
    private var primerText: String {
        if Self.hasAllPermissions {
            return "A short tour explains what you're about to see."
        }
        return "A short tour explains what you're about to see. "
            + "Firmament needs your camera to draw markers over the sky, "
            + "and your location to know which markers are above you."
    }

    private static var hasAllPermissions: Bool {
        let cameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        let locationStatus = CLLocationManager().authorizationStatus
        let locationGranted = locationStatus == .authorizedWhenInUse || locationStatus == .authorizedAlways
        return cameraGranted && locationGranted
    }

    /// Requests access, then runs `completion` — either starting the tour or
    /// skipping it. Both paths need camera + location, so the request is the
    /// same; only the terminal action differs.
    private func beginRequests(then completion: @escaping () -> Void) {
        guard !isRequesting else { return }
        isRequesting = true
        Log.info("intro.permissions.requested")
        Task {
            let cameraGranted = await AVCaptureDevice.requestAccess(for: .video)
            locationProvider.start()
            let deadline = Date.now.addingTimeInterval(Self.locationResolutionTimeout)
            while !locationProvider.authorizationResolved && Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            Log.info("intro.permissions.resolved", [
                "camera_granted": cameraGranted,
                "location_resolved": locationProvider.authorizationResolved,
                "location_denied": locationProvider.isDenied
            ])
            completion()
        }
    }
}

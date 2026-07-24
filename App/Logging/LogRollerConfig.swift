import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Configuration for the LogRoller transport, resolved in priority:
///
/// 1. Environment variable (simulator / Xcode scheme overrides)
/// 2. Info.plist key (via the xcodegen generator)
/// 3. Compiled-in default
///
/// Only DEBUG builds enable the transport by default; release builds need
/// `LOGROLLER_ENABLED=1` explicitly, which never happens in shipped binaries.
nonisolated struct LogRollerConfig: Sendable {
    let baseURL: URL
    let runID: String
    let deviceID: String
    let isEnabled: Bool

    /// Default base URL — the developer's Mac running LogRoller on the LAN.
    /// Override with `LOGROLLER_BASE_URL` (env var or Info.plist) when it moves.
    static let defaultBaseURLString = "https://192.168.1.230:8443"

    @MainActor
    static func resolved() -> LogRollerConfig {
        let env = ProcessInfo.processInfo.environment

        let urlString = env["LOGROLLER_BASE_URL"]
            ?? infoPlistString("LOGROLLER_BASE_URL")
            ?? defaultBaseURLString
        let baseURL = URL(string: urlString) ?? URL(fileURLWithPath: "/")

        let runID = env["LOGROLLER_RUN_ID"]
            ?? infoPlistString("LOGROLLER_RUN_ID")
            ?? makeDefaultRunID()

        let deviceID = env["LOGROLLER_DEVICE_ID"]
            ?? infoPlistString("LOGROLLER_DEVICE_ID")
            ?? Self.persistentDeviceID()

        let isEnabled: Bool = {
            if let raw = env["LOGROLLER_ENABLED"] {
                return raw == "1" || raw.lowercased() == "true"
            }
            #if DEBUG
            return true
            #else
            return false
            #endif
        }()

        return LogRollerConfig(baseURL: baseURL, runID: runID, deviceID: deviceID, isEnabled: isEnabled)
    }

    // MARK: - Helpers

    private static func infoPlistString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    private static func makeDefaultRunID() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let stamp = formatter.string(from: .now).replacing(":", with: "")
        let suffix = String(UUID().uuidString.prefix(8))
        return "firmament-\(stamp)-\(suffix)"
    }

    private static let deviceIDDefaultsKey = "org.akuaku.firmament.logroller.deviceID"

    /// `identifierForVendor` when available (stable across launches for the same
    /// vendor on the same device); otherwise a one-time UUID in UserDefaults.
    @MainActor
    private static func persistentDeviceID() -> String {
        #if canImport(UIKit)
        if let vendorID = UIDevice.current.identifierForVendor?.uuidString {
            return "ios-\(vendorID.prefix(12))"
        }
        #endif
        let defaults = UserDefaults.standard
        if let saved = defaults.string(forKey: deviceIDDefaultsKey) {
            return saved
        }
        let fresh = "anon-\(UUID().uuidString.prefix(12))"
        defaults.set(fresh, forKey: deviceIDDefaultsKey)
        return fresh
    }
}

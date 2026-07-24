import SwiftUI

@main
struct FirmamentApp: App {
    private let logRoller: LogRollerClient
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // App-level logging first, so everything below can report through it:
        // OSLog always, plus LogRoller when configured and the server is reachable.
        let logConfig = LogRollerConfig.resolved()
        let logRoller = LogRollerClient(config: logConfig)
        self.logRoller = logRoller
        Log.bind(logRoller)
        Task { await logRoller.start() }
        Log.info("app.launched", [
            "logroller_enabled": logConfig.isEnabled,
            "logroller_url": logConfig.baseURL.absoluteString,
            "run_id": logConfig.runID,
            "device_id": logConfig.deviceID
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .onChange(of: scenePhase) { previous, current in
            Log.info("app.scenePhase", ["from": String(describing: previous), "to": String(describing: current)])
            // Ship buffered events before the OS may suspend us.
            if current == .background {
                let client = logRoller
                Task { await client.flushNow() }
            }
        }
    }
}

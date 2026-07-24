import Foundation
import os

/// Application-wide logging facade. Every emit fans out to two destinations:
///
/// 1. Apple's unified log via `os.Logger` — shows up in Console.app and
///    `xcrun simctl spawn ... log show` immediately, the usual OSLog way.
/// 2. The shared `LogRollerClient` (when configured via `Log.bind(_:)` and the
///    server is reachable), which batches and ships to the developer's local
///    LogRoller for Claude-readable inspection. If LogRoller isn't configured or
///    the server is down, this is a silent no-op — the app is unaffected.
///
/// Call sites stay synchronous and cheap; LogRoller delivery is fired into a Task.
/// Four levels: `debug`, `info`, `warn`, `error`.
///
/// ## Event catalog
/// Firmament's render loop runs at 2 Hz over up to ~2,000 nodes, so logging is
/// deliberately coarse: **no per-frame or per-node events.** The stable event
/// names in use, grouped:
/// - `app.*` — launch, scenePhase.
/// - `ar.*` — session start, failure, interruption, camera tracking-state
///   transitions (emitted only on change, never per frame).
/// - `location.*` — start, denied, first fix.
/// - `render.summary` — a throttled (~10 s) heartbeat carrying node counts, the
///   observer's astronomical state, and the active configuration.
/// - `render.config` — emitted once when settings change (bounded, event-driven).
/// - `render.nodesCapped` — emitted only when the candidate set crosses the
///   render budget (saturation transitions), not every saturated tick.
/// - `ui.*` — low-frequency user interactions (opening panels, toggles).
enum Log {
    private static let logger = Logger(subsystem: "org.akuaku.firmament", category: "app")
    nonisolated(unsafe) private static var client: LogRollerClient?
    private static let lock = NSLock()

    /// Hook the LogRoller client up so `Log.info(...)` etc. forward to it. Safe to
    /// call once at app start; subsequent calls overwrite. Pass nil to detach.
    static func bind(_ client: LogRollerClient?) {
        lock.lock()
        defer { lock.unlock() }
        Self.client = client
    }

    static func debug(_ event: String, _ payload: [String: Any?] = [:]) { emit(.debug, event: event, payload: payload) }
    static func info(_ event: String, _ payload: [String: Any?] = [:]) { emit(.info, event: event, payload: payload) }
    static func warn(_ event: String, _ payload: [String: Any?] = [:]) { emit(.warn, event: event, payload: payload) }
    static func error(_ event: String, _ payload: [String: Any?] = [:]) { emit(.error, event: event, payload: payload) }

    private static func emit(_ level: LogRollerEvent.Level, event: String, payload: [String: Any?]) {
        // Snapshot resident memory before the os.Logger call so the value the
        // LogRoller event carries is consistent and a slow sink can't skew it.
        let memoryBytes = currentResidentBytes()

        let summary = payloadSummary(payload)
        switch level {
        case .debug: logger.debug("\(event, privacy: .public) \(summary, privacy: .public)")
        case .info: logger.info("\(event, privacy: .public) \(summary, privacy: .public)")
        case .warn: logger.warning("\(event, privacy: .public) \(summary, privacy: .public)")
        case .error: logger.error("\(event, privacy: .public) \(summary, privacy: .public)")
        }

        let snapshot: LogRollerClient? = {
            lock.lock(); defer { lock.unlock() }
            return client
        }()
        guard let snapshot else { return }

        let wrapped = payload.mapValues { AnyCodable.wrap($0) }
        let resources = memoryBytes.map { Resources(memoryBytes: $0) }
        Task { await snapshot.emit(level: level, event: event, payload: wrapped, resources: resources) }
    }

    /// Current resident memory (RSS) in bytes via `mach_task_basic_info`; nil only
    /// if the syscall fails. Same number Xcode's gauges show.
    private static func currentResidentBytes() -> Int? {
        var info = mach_task_basic_info()
        let infoCount = MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size
        var count = mach_msg_type_number_t(infoCount)
        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPtr in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), reboundPtr, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return Int(info.resident_size)
    }

    private static func payloadSummary(_ payload: [String: Any?]) -> String {
        guard !payload.isEmpty else { return "" }
        let pairs = payload
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\(String(describing: $0.value ?? "nil"))" }
        return "{\(pairs.joined(separator: " "))}"
    }
}

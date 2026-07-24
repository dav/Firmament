import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Buffered, async-safe LogRoller transport.
///
/// Events are enqueued from any actor; a periodic flush task drains the queue in
/// batches via `POST /ingest`. `final actor` so callers fire-and-forget.
///
/// **URLSession lifecycle** (per the LogRoller skill warning): on iOS the OS may
/// invalidate `URLSession` during app suspension. If a flush fires after that,
/// `data(for:)` on the dead session throws an *uncatchable* ObjC
/// `NSGenericException` and crashes. Mitigated by creating the session lazily,
/// recreating it in the flush `catch`, and never calling `invalidateAndCancel()`.
final actor LogRollerClient {
    private let config: LogRollerConfig
    private let flushInterval: Duration
    private let maxBatchSize: Int
    private let maxQueueSize: Int
    private let appInfo: AppInfo

    private var queue: [LogRollerEvent] = []
    private var nextSeq: Int = 0
    private var flushTask: Task<Void, Never>?
    private var session: URLSession?
    nonisolated private let trustDelegate: TrustEverythingDelegate?

    init(
        config: LogRollerConfig,
        flushInterval: Duration = .seconds(2),
        maxBatchSize: Int = 100,
        maxQueueSize: Int = 1_000
    ) {
        self.config = config
        self.flushInterval = flushInterval
        self.maxBatchSize = maxBatchSize
        self.maxQueueSize = maxQueueSize
        self.appInfo = .fromMainBundle()
        // mkcert's root CA isn't trusted by iOS; in DEBUG we accept the local cert
        // without validation. Release builds must trust the CA out-of-band, so the
        // delegate is nil there (and the transport is off by default anyway).
        #if DEBUG
        self.trustDelegate = TrustEverythingDelegate()
        #else
        self.trustDelegate = nil
        #endif
    }

    /// Begin the periodic-flush loop. Idempotent; no-op when disabled.
    func start() {
        guard config.isEnabled, flushTask == nil else { return }
        flushTask = Task { [weak self] in await self?.flushLoop() }
    }

    /// Enqueue one event. Drops oldest on overflow so logging never back-pressures
    /// the app.
    func emit(
        level: LogRollerEvent.Level,
        event: String,
        payload: [String: AnyCodable],
        resources: Resources? = nil
    ) {
        guard config.isEnabled else { return }
        let entry = LogRollerEvent(
            ts: Self.timestamp(),
            level: level,
            event: event,
            seq: nextSeq,
            payload: payload,
            app: appInfo,
            resources: resources
        )
        nextSeq += 1
        queue.append(entry)
        if queue.count > maxQueueSize {
            queue.removeFirst(queue.count - maxQueueSize)
        }
    }

    /// Drain the queue immediately — call at app backgrounding so events don't wait
    /// for the next interval (or get lost to suspension).
    func flushNow() async {
        await flushPendingEvents()
    }

    // MARK: - Internal

    private func flushLoop() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: flushInterval)
            } catch {
                return // cancelled
            }
            await flushPendingEvents()
        }
    }

    private func flushPendingEvents() async {
        guard !queue.isEmpty else { return }
        let drained = Array(queue.prefix(maxBatchSize))
        queue.removeFirst(drained.count)
        let batch = LogRollerBatch(runId: config.runID, deviceId: config.deviceID, events: drained)
        await deliver(batch)
    }

    private func deliver(_ batch: LogRollerBatch) async {
        guard let endpoint = URL(string: "/ingest", relativeTo: config.baseURL)?.absoluteURL else { return }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(batch)
        } catch {
            return // shouldn't happen with our value types
        }

        do {
            _ = try await ensureSession().data(for: request)
        } catch {
            // Per the skill: nil the session so the next flush makes a fresh one.
            session = nil
            #if DEBUG
            print("[LogRoller] flush failed: \(error.localizedDescription)")
            #endif
        }
    }

    private func ensureSession() -> URLSession {
        if let session { return session }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.waitsForConnectivity = false
        let new = URLSession(configuration: configuration, delegate: trustDelegate, delegateQueue: nil)
        session = new
        return new
    }

    nonisolated private static func timestamp() -> String {
        Date.now.formatted(.iso8601
            .year().month().day()
            .timeZone(separator: .omitted)
            .time(includingFractionalSeconds: true)
            .timeSeparator(.colon))
    }
}

/// DEBUG-only delegate that accepts the server cert. Lets the app talk to the
/// developer's mkcert-signed local LogRoller without installing the root CA on the
/// device. Never compiled into release builds.
private final class TrustEverythingDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        completionHandler(.performDefaultHandling, nil)
    }
}

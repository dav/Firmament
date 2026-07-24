import Foundation

/// One event posted to LogRoller's `/ingest` endpoint. Mirrors the contract from
/// `logroller ingest-help --json`: required `ts`/`level`/`event`/`payload`, with
/// `seq`/`app`/`resources` indexed out-of-band.
nonisolated struct LogRollerEvent: Sendable, Codable {
    enum Level: String, Sendable, Codable {
        case debug, info, warn, error
    }

    let ts: String           // ISO-8601 UTC
    let level: Level
    let event: String
    let seq: Int
    let payload: [String: AnyCodable]
    let app: AppInfo?
    let resources: Resources?

    init(
        ts: String,
        level: Level,
        event: String,
        seq: Int,
        payload: [String: AnyCodable],
        app: AppInfo? = nil,
        resources: Resources? = nil
    ) {
        self.ts = ts
        self.level = level
        self.event = event
        self.seq = seq
        self.payload = payload
        self.app = app
        self.resources = resources
    }

    enum CodingKeys: String, CodingKey { case ts, level, event, seq, payload, app, resources }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ts, forKey: .ts)
        try container.encode(level, forKey: .level)
        try container.encode(event, forKey: .event)
        try container.encode(seq, forKey: .seq)
        try container.encode(payload, forKey: .payload)
        try container.encodeIfPresent(app, forKey: .app)
        try container.encodeIfPresent(resources, forKey: .resources)
    }
}

/// Application-build metadata, constant for the life of a process — attached to
/// every event so LogRoller can bucket / diff by build, version, and env.
nonisolated struct AppInfo: Sendable, Codable {
    let name: String?
    let version: String?
    let build: String?
    let env: String?

    enum CodingKeys: String, CodingKey { case name, version, build, env }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(version, forKey: .version)
        try container.encodeIfPresent(build, forKey: .build)
        try container.encodeIfPresent(env, forKey: .env)
    }

    static func fromMainBundle() -> AppInfo {
        let bundle = Bundle.main
        return AppInfo(
            name: bundle.object(forInfoDictionaryKey: "CFBundleName") as? String,
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
            env: Self.environment
        )
    }

    private static var environment: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}

/// Per-emit resource snapshot, in the dedicated `resources` block so LogRoller can
/// chart memory across runs without inspecting individual event shapes.
nonisolated struct Resources: Sendable, Codable {
    let memoryBytes: Int?

    enum CodingKeys: String, CodingKey { case memoryBytes = "memory_bytes" }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(memoryBytes, forKey: .memoryBytes)
    }
}

/// Batch envelope. Empty `events` arrays are never posted.
nonisolated struct LogRollerBatch: Sendable, Codable {
    let runId: String
    let deviceId: String
    let events: [LogRollerEvent]

    enum CodingKeys: String, CodingKey {
        case runId = "run_id"
        case deviceId = "device_id"
        case events
    }
}

/// Tiny `Any`-equivalent that survives JSON round-trips, since `payload` is a
/// free-form object and `[String: Any]` isn't directly Codable.
nonisolated enum AnyCodable: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([AnyCodable])
    case object([String: AnyCodable])
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AnyCodable].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AnyCodable].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    /// Map common Swift values into AnyCodable; anything unknown is stringified.
    static func wrap(_ value: Any?) -> AnyCodable {
        switch value {
        case nil, is NSNull: return .null
        case let value as Bool: return .bool(value)
        case let value as Int: return .int(value)
        case let value as Int64: return .int(Int(value))
        case let value as Double: return .double(value)
        case let value as Float: return .double(Double(value))
        case let value as String: return .string(value)
        case let value as [Any?]: return .array(value.map { wrap($0) })
        case let value as [String: Any?]: return .object(value.mapValues { wrap($0) })
        default: return .string(String(describing: value as Any))
        }
    }
}

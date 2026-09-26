import Foundation

/// One Codex CLI session, from a `sessions/YYYY/MM/DD/rollout-*.jsonl` file.
public struct CodexSession: Hashable, Sendable {
    public struct TokenSample: Hashable, Sendable {
        public var date: Date
        /// Running total for the session so far.
        public var total: Int
    }

    public var id: String
    public var start: Date?
    public var end: Date?
    public var cwd: String?
    /// Empty when the Codex version that wrote the file logged no token counts.
    public var tokenSamples: [TokenSample] = []
    public var rateLimits: CodexRateLimits?

    public init(id: String) {
        self.id = id
    }

    public var hasTokenData: Bool { !tokenSamples.isEmpty }

    /// Tokens used inside `interval`, from the growth of the running total.
    public func tokens(in interval: DateInterval) -> Int {
        var previous = 0
        var sum = 0
        for sample in tokenSamples {
            let delta = max(sample.total - previous, 0)
            previous = max(previous, sample.total)
            if interval.contains(sample.date) { sum += delta }
        }
        return sum
    }

    /// Time between the first and last event, clipped to `interval`.
    public func activeTime(in interval: DateInterval) -> TimeInterval {
        guard let start, let end else { return 0 }
        let lower = max(start, interval.start)
        let upper = min(end, interval.end)
        return max(upper.timeIntervalSince(lower), 0)
    }

    public func overlaps(_ interval: DateInterval) -> Bool {
        guard let start else { return false }
        return start <= interval.end && (end ?? start) >= interval.start
    }
}

/// The plan limits Codex reports alongside token counts, when it does.
public struct CodexRateLimits: Hashable, Sendable {
    public struct Window: Hashable, Sendable {
        public var usedPercent: Double
        public var windowMinutes: Int?
        public var resetsAt: Date?
    }

    /// Usually the 5-hour window.
    public var primary: Window?
    /// Usually the weekly window.
    public var secondary: Window?
    public var observedAt: Date
}

/// Parses a rollout file line by line, so it can be fed incrementally. Tolerates both
/// the early format (a bare header line, no per-line timestamps) and the newer
/// `session_meta` / `event_msg` format; token counts are read only if present.
public struct CodexLogParser: Sendable {
    public private(set) var session: CodexSession

    public init(fileName: String) {
        session = CodexSession(id: (fileName as NSString).deletingPathExtension)
    }

    public mutating func consume(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        let date = (object["timestamp"] as? String).flatMap(Timestamp.parse)
        if let date { note(date) }

        let type = object["type"] as? String
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch type {
        case "session_meta":
            if let id = payload["id"] as? String { session.id = id }
            if let started = (payload["timestamp"] as? String).flatMap(Timestamp.parse) {
                session.start = min(session.start ?? started, started)
            }
            if let cwd = payload["cwd"] as? String { session.cwd = cwd }
        case "turn_context":
            if session.cwd == nil, let cwd = payload["cwd"] as? String { session.cwd = cwd }
        case "event_msg":
            if payload["type"] as? String == "token_count", let date {
                readTokenCount(payload, at: date)
            }
        case nil:
            // Early format header: {"id": …, "timestamp": …, "instructions": …}
            if object["record_type"] == nil, let id = object["id"] as? String, date != nil {
                session.id = id
            }
        default:
            break
        }
    }

    private mutating func note(_ date: Date) {
        session.start = min(session.start ?? date, date)
        session.end = max(session.end ?? date, date)
    }

    private mutating func readTokenCount(_ payload: [String: Any], at date: Date) {
        let info = payload["info"] as? [String: Any]
        let usage = info?["total_token_usage"] as? [String: Any] ?? (info == nil ? payload : nil)
        if let total = Self.int(usage?["total_tokens"]) {
            session.tokenSamples.append(.init(date: date, total: total))
        }
        if let limits = payload["rate_limits"] as? [String: Any] {
            let primary = Self.window(limits["primary"], at: date)
            let secondary = Self.window(limits["secondary"], at: date)
            if primary != nil || secondary != nil {
                session.rateLimits = CodexRateLimits(primary: primary, secondary: secondary, observedAt: date)
            }
        }
    }

    private static func window(_ value: Any?, at date: Date) -> CodexRateLimits.Window? {
        guard let dict = value as? [String: Any], let used = double(dict["used_percent"]) else { return nil }
        var resetsAt: Date?
        if let at = double(dict["resets_at"]) {
            resetsAt = Date(timeIntervalSince1970: at)
        } else if let seconds = double(dict["resets_in_seconds"]) {
            resetsAt = date.addingTimeInterval(seconds)
        }
        return .init(usedPercent: used, windowMinutes: int(dict["window_minutes"]), resetsAt: resetsAt)
    }

    private static func int(_ value: Any?) -> Int? {
        (value as? NSNumber)?.intValue
    }

    private static func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}

import Foundation

/// Token counts for one message or a sum of messages, split the way they are billed.
public struct TokenCounts: Hashable, Sendable, Codable {
    public var input = 0
    public var output = 0
    public var cacheWrite5m = 0
    public var cacheWrite1h = 0
    public var cacheRead = 0

    public init(input: Int = 0, output: Int = 0, cacheWrite5m: Int = 0, cacheWrite1h: Int = 0, cacheRead: Int = 0) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
    }

    public var cacheWrite: Int { cacheWrite5m + cacheWrite1h }

    /// Every token the model processed, cache reads included, as ccusage counts them.
    public var total: Int { input + output + cacheWrite5m + cacheWrite1h + cacheRead }

    public var isEmpty: Bool { total == 0 }

    public static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h,
            cacheRead: lhs.cacheRead + rhs.cacheRead
        )
    }

    public static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }

    /// Field-wise maximum. A streamed message is logged several times with growing
    /// counts, so the largest value of each field is the final one.
    public func union(_ other: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: max(input, other.input),
            output: max(output, other.output),
            cacheWrite5m: max(cacheWrite5m, other.cacheWrite5m),
            cacheWrite1h: max(cacheWrite1h, other.cacheWrite1h),
            cacheRead: max(cacheRead, other.cacheRead)
        )
    }
}

/// One Claude Code API response, after deduplication.
public struct UsageEntry: Hashable, Sendable {
    public var date: Date
    public var model: String
    public var tokens: TokenCounts
    /// The transcript folder under `projects/`, e.g. `-Users-me-code-app`.
    public var project: String
    public var session: String
    /// API list-price equivalent, filled in when a report is built; nil when no price is known.
    public var cost: Double?

    public init(date: Date, model: String, tokens: TokenCounts, project: String, session: String, cost: Double? = nil) {
        self.date = date
        self.model = model
        self.tokens = tokens
        self.project = project
        self.session = session
        self.cost = cost
    }
}

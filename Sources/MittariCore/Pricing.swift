import Foundation

/// Prices for one stretch of time, in USD per million tokens. A missing price means
/// unknown: usage that needs it gets no cost rather than a made-up one.
public struct PricePeriod: Codable, Hashable, Sendable, Identifiable {
    public var id = UUID()
    /// First day these prices apply; nil means since the model was released.
    public var from: Date?
    /// First day they no longer apply; nil means until a later period starts.
    public var to: Date?
    public var input: Double?
    public var output: Double?
    public var cacheWrite5m: Double?
    public var cacheWrite1h: Double?
    public var cacheRead: Double?
    /// Where the numbers come from, shown in Settings.
    public var source: String?

    public init(from: Date? = nil, to: Date? = nil, input: Double?, output: Double?,
                cacheWrite5m: Double?, cacheWrite1h: Double?, cacheRead: Double?, source: String? = nil) {
        self.from = from
        self.to = to
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
        self.cacheRead = cacheRead
        self.source = source
    }

    public func contains(_ date: Date) -> Bool {
        (from.map { date >= $0 } ?? true) && (to.map { date < $0 } ?? true)
    }

    /// API list-price equivalent of `tokens`, or nil if a price it needs is missing.
    public func cost(of tokens: TokenCounts) -> Double? {
        let parts: [(Int, Double?)] = [
            (tokens.input, input), (tokens.output, output),
            (tokens.cacheWrite5m, cacheWrite5m), (tokens.cacheWrite1h, cacheWrite1h),
            (tokens.cacheRead, cacheRead),
        ]
        var total = 0.0
        for (count, price) in parts where count > 0 {
            guard let price else { return nil }
            total += Double(count) * price
        }
        return total / 1_000_000
    }
}

/// The price history of one model.
public struct ModelPricing: Codable, Hashable, Sendable, Identifiable {
    /// Normalized model ID, e.g. `claude-opus-5`.
    public var id: String
    public var periods: [PricePeriod]

    public init(id: String, periods: [PricePeriod]) {
        self.id = id
        self.periods = periods
    }

    /// The period in effect at `date`. When periods overlap, the one that started last wins,
    /// so adding "new prices from <date>" is enough to supersede an open-ended period.
    public func period(at date: Date) -> PricePeriod? {
        periods.filter { $0.contains(date) }.max { ($0.from ?? .distantPast) < ($1.from ?? .distantPast) }
    }
}

/// All known prices. Each message is priced with the period valid at its own timestamp,
/// so past usage keeps its historical cost when prices change.
public struct PriceBook: Codable, Hashable, Sendable {
    public var models: [ModelPricing]
    /// When the defaults were last checked against Anthropic's pricing page.
    public var lastVerified: Date?

    public init(models: [ModelPricing], lastVerified: Date?) {
        self.models = models
        self.lastVerified = lastVerified
    }

    public func pricing(for model: String) -> ModelPricing? {
        let id = ModelName.normalize(model)
        return models.first { $0.id == id }
    }

    public func cost(of tokens: TokenCounts, model: String, at date: Date) -> Double? {
        pricing(for: model)?.period(at: date)?.cost(of: tokens)
    }

    public static let sourceURL = "https://platform.claude.com/docs/en/about-claude/pricing"

    /// Official Anthropic API list prices (USD per million tokens: input, 5-minute cache
    /// write, 1-hour cache write, cache read, output), copied from the "Model pricing" table
    /// at https://platform.claude.com/docs/en/about-claude/pricing on 2026-09-26.
    /// That page lists no earlier prices for these models (Sonnet 5's launch price was
    /// made permanent, per its footnote), so each model has a single period since release.
    public static let defaults: PriceBook = {
        let source = "Anthropic pricing page, verified 2026-09-26"
        func model(_ id: String, _ input: Double, _ write5m: Double, _ write1h: Double, _ read: Double, _ output: Double) -> ModelPricing {
            ModelPricing(id: id, periods: [PricePeriod(
                input: input, output: output, cacheWrite5m: write5m, cacheWrite1h: write1h, cacheRead: read, source: source
            )])
        }
        return PriceBook(models: [
            model("claude-fable-5-1", 10, 12.5, 20, 0.25, 50),
            model("claude-fable-5", 10, 12.5, 20, 1, 50),
            model("claude-opus-5-5", 4, 5, 8, 0.2, 20),
            model("claude-opus-5", 5, 6.25, 10, 0.5, 25),
            model("claude-opus-4-8", 5, 6.25, 10, 0.5, 25),
            model("claude-opus-4-7", 5, 6.25, 10, 0.5, 25),
            model("claude-opus-4-6", 5, 6.25, 10, 0.5, 25),
            model("claude-opus-4-5", 5, 6.25, 10, 0.5, 25),
            model("claude-opus-4-1", 15, 18.75, 30, 1.5, 75),
            model("claude-opus-4", 15, 18.75, 30, 1.5, 75),
            model("claude-sonnet-5", 2, 2.5, 4, 0.2, 10),
            model("claude-sonnet-4-6", 3, 3.75, 6, 0.3, 15),
            model("claude-sonnet-4-5", 3, 3.75, 6, 0.3, 15),
            model("claude-sonnet-4", 3, 3.75, 6, 0.3, 15),
            model("claude-haiku-4-5", 1, 1.25, 2, 0.1, 5),
            model("claude-3-5-haiku", 0.8, 1, 1.6, 0.08, 4),
        ], lastVerified: Timestamp.parse("2026-09-26T00:00:00Z"))
    }()
}

/// Model ID helpers.
public enum ModelName {
    /// Strips what varies between otherwise identical models: a `[1m]` context tag, a
    /// release date, a cloud provider prefix or version suffix.
    public static func normalize(_ model: String) -> String {
        var id = model.lowercased()
        if let bracket = id.firstIndex(of: "[") { id = String(id[..<bracket]) }
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }
        if let range = id.range(of: "anthropic.") { id = String(id[range.upperBound...]) }
        if let colon = id.firstIndex(of: ":") { id = String(id[..<colon]) }
        if id.hasSuffix("-v1") { id.removeLast(3) }
        let parts = id.split(separator: "-")
        if let last = parts.last, last.count == 8, last.allSatisfy(\.isNumber) {
            id = parts.dropLast().joined(separator: "-")
        }
        return id
    }

    /// Readable name: `claude-opus-5-5` becomes "Opus 5.5", `claude-3-5-haiku` "Haiku 3.5".
    public static func display(_ model: String) -> String {
        let id = normalize(model)
        var parts = id.split(separator: "-").map(String.init)
        if parts.first == "claude" { parts.removeFirst() }
        let words = parts.filter { !$0.allSatisfy(\.isNumber) }
        let numbers = parts.filter { $0.allSatisfy(\.isNumber) }
        guard !words.isEmpty else { return model }
        let name = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return numbers.isEmpty ? name : "\(name) \(numbers.joined(separator: "."))"
    }
}

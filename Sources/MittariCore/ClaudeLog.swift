import Foundation

/// Reads usage out of Claude Code transcripts (`projects/<folder>/*.jsonl`, including
/// the `subagents/` files below each session, which are billed like any other request).
public enum ClaudeLog {
    /// One assistant line with usage.
    public struct Record: Sendable {
        /// `message.id` + `requestId`: the same response is logged once per content block
        /// and again when a session is resumed, so this is what deduplicates it.
        public var key: String?
        public var entry: UsageEntry
        public var cwd: String?
    }

    /// Cheap byte checks before decoding: only assistant lines carry usage.
    public static func mightContainUsage(_ line: UnsafeRawBufferPointer) -> Bool {
        contains(line, usageMarker) && contains(line, assistantMarker)
    }

    public static func parse(line: Data, project: String) -> Record? {
        let isCandidate = line.withUnsafeBytes { mightContainUsage($0) }
        guard isCandidate, let decoded = try? decoder.decode(Line.self, from: line) else { return nil }
        return record(from: decoded, project: project)
    }

    static func record(from line: Line, project: String) -> Record? {
        guard line.type == "assistant", let message = line.message, let usage = message.usage,
              let stamp = line.timestamp, let date = Timestamp.parse(stamp) else { return nil }
        let model = message.model ?? "unknown"
        // Placeholder messages Claude Code writes itself (errors, interruptions).
        guard model != "<synthetic>" else { return nil }

        let created = usage.cache_creation_input_tokens ?? 0
        var write5m = created
        var write1h = 0
        if let split = usage.cache_creation {
            write5m = split.ephemeral_5m_input_tokens ?? 0
            write1h = split.ephemeral_1h_input_tokens ?? 0
            // Keep the total authoritative if the split doesn't add up.
            if write5m + write1h != created { write5m = max(created - write1h, 0) }
        }
        let tokens = TokenCounts(
            input: usage.input_tokens ?? 0,
            output: usage.output_tokens ?? 0,
            cacheWrite5m: write5m,
            cacheWrite1h: write1h,
            cacheRead: usage.cache_read_input_tokens ?? 0
        )
        guard !tokens.isEmpty else { return nil }

        let key: String? = (message.id == nil && line.requestId == nil) ? nil : "\(message.id ?? ""):\(line.requestId ?? "")"
        let entry = UsageEntry(date: date, model: model, tokens: tokens, project: project, session: line.sessionId ?? "")
        return Record(key: key, entry: entry, cwd: line.cwd)
    }

    struct Line: Decodable {
        var type: String?
        var timestamp: String?
        var requestId: String?
        var sessionId: String?
        var cwd: String?
        var message: Message?

        struct Message: Decodable {
            var id: String?
            var model: String?
            var usage: Usage?
        }

        struct Usage: Decodable {
            var input_tokens: Int?
            var output_tokens: Int?
            var cache_creation_input_tokens: Int?
            var cache_read_input_tokens: Int?
            var cache_creation: CacheCreation?
        }

        struct CacheCreation: Decodable {
            var ephemeral_5m_input_tokens: Int?
            var ephemeral_1h_input_tokens: Int?
        }
    }

    private static let decoder = JSONDecoder()
    private static let usageMarker = Array(#""usage""#.utf8)
    private static let assistantMarker = Array(#""assistant""#.utf8)

    static func contains(_ haystack: UnsafeRawBufferPointer, _ needle: [UInt8]) -> Bool {
        guard let base = haystack.baseAddress, haystack.count >= needle.count else { return false }
        return needle.withUnsafeBytes { n in
            memmem(base, haystack.count, n.baseAddress, n.count) != nil
        }
    }
}

/// Deduplicated usage, keyed by message and request ID.
public struct UsageLedger: Sendable {
    private var items: [UsageEntry] = []
    /// Position in `items` of each keyed entry.
    private var index: [String: Int] = [:]
    /// New lines are usually the newest, so `items` mostly stays in date order and only
    /// needs sorting after an initial scan.
    private var isSorted = true

    public init() {}

    public var count: Int { items.count }

    /// Adds a record, merging it with an earlier copy of the same response: the earliest
    /// timestamp and the largest count of each kind win, since streamed copies grow.
    public mutating func add(_ record: ClaudeLog.Record) {
        guard let key = record.key else {
            append(record.entry)
            return
        }
        if let position = index[key] {
            items[position].tokens = items[position].tokens.union(record.entry.tokens)
            if record.entry.date < items[position].date {
                items[position].date = record.entry.date
                isSorted = false
            }
        } else {
            index[key] = items.count
            append(record.entry)
        }
    }

    private mutating func append(_ entry: UsageEntry) {
        if let last = items.last, entry.date < last.date { isSorted = false }
        items.append(entry)
    }

    /// Puts entries in date order, keeping keys pointing at the right positions.
    public mutating func sort() {
        guard !isSorted else { return }
        let keyOf = Dictionary(uniqueKeysWithValues: index.map { ($0.value, $0.key) })
        let order = items.indices.sorted { items[$0].date < items[$1].date }
        var newIndex: [String: Int] = [:]
        newIndex.reserveCapacity(index.count)
        for (newPosition, oldPosition) in order.enumerated() {
            if let key = keyOf[oldPosition] { newIndex[key] = newPosition }
        }
        items = order.map { items[$0] }
        index = newIndex
        isSorted = true
    }

    /// Drops entries older than `date`, to bound memory.
    public mutating func prune(before date: Date) {
        guard items.contains(where: { $0.date < date }) else { return }
        let keyOf = Dictionary(uniqueKeysWithValues: index.map { ($0.value, $0.key) })
        var kept: [UsageEntry] = []
        var newIndex: [String: Int] = [:]
        for (position, entry) in items.enumerated() where entry.date >= date {
            if let key = keyOf[position] { newIndex[key] = kept.count }
            kept.append(entry)
        }
        items = kept
        index = newIndex
    }

    /// All entries, oldest first.
    public var entries: [UsageEntry] {
        isSorted ? items : items.sorted { $0.date < $1.date }
    }
}

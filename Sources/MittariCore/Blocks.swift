import Foundation

/// A 5-hour usage window, grouped the way ccusage does it: a window opens at the first
/// message (floored to the hour) and lasts five hours; the next message after it closes,
/// or after five idle hours, opens a new one.
public struct UsageBlock: Hashable, Sendable, Identifiable {
    public var start: Date
    public var lastActivity: Date
    public var tokens = TokenCounts()
    public var cost = 0.0
    /// Tokens in this window from models without a known price.
    public var unpricedTokens = 0
    public var messageCount = 0

    public var id: Date { start }
    public var end: Date { start.addingTimeInterval(Blocks.duration) }

    public func contains(_ date: Date) -> Bool { date >= start && date < end }
}

public enum Blocks {
    public static let duration: TimeInterval = 5 * 3600

    /// Groups entries (in any order) into blocks, oldest first.
    public static func compute(_ entries: [UsageEntry]) -> [UsageBlock] {
        let sorted = entries.sorted { $0.date < $1.date }
        var blocks: [UsageBlock] = []
        for entry in sorted {
            if var block = blocks.last,
               entry.date < block.end,
               entry.date.timeIntervalSince(block.lastActivity) < duration {
                add(entry, to: &block)
                blocks[blocks.count - 1] = block
            } else {
                var block = UsageBlock(start: floorToHour(entry.date), lastActivity: entry.date)
                add(entry, to: &block)
                blocks.append(block)
            }
        }
        return blocks
    }

    /// The window that contains `now`, if any message opened one.
    public static func current(in blocks: [UsageBlock], now: Date) -> UsageBlock? {
        guard let last = blocks.last, last.contains(now) else { return nil }
        return last
    }

    /// Hours are floored in UTC, like ccusage.
    public static func floorToHour(_ date: Date) -> Date {
        Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
    }

    private static func add(_ entry: UsageEntry, to block: inout UsageBlock) {
        block.tokens += entry.tokens
        block.lastActivity = max(block.lastActivity, entry.date)
        block.messageCount += 1
        if let cost = entry.cost {
            block.cost += cost
        } else {
            block.unpricedTokens += entry.tokens.total
        }
    }
}

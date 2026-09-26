import Foundation

/// Tokens and API list-price equivalent over some span.
public struct Totals: Hashable, Sendable {
    public var tokens = TokenCounts()
    public var cost = 0.0
    /// Tokens that could not be priced (unknown model or missing price).
    public var unpricedTokens = 0
    public var messages = 0

    public init() {}

    public var isEmpty: Bool { messages == 0 }
    /// Cost is only a lower bound when some usage had no price.
    public var costIsPartial: Bool { unpricedTokens > 0 }

    public mutating func add(_ entry: UsageEntry) {
        tokens += entry.tokens
        messages += 1
        if let cost = entry.cost {
            self.cost += cost
        } else {
            unpricedTokens += entry.tokens.total
        }
    }
}

/// A named share of usage: a model or a project.
public struct Slice: Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var totals = Totals()
}

public struct CodexSummary: Hashable, Sendable {
    public var folderExists = false
    public var sessionCount = 0
    public var sessionsToday = 0
    public var activeToday: TimeInterval = 0
    /// Nil when no session logged token counts.
    public var tokensToday: Int?
    public var tokensWeek: Int?
    /// The most recent limits Codex reported, if any.
    public var rateLimits: CodexRateLimits?
    public var lastActivity: Date?

    public init() {}
}

/// Everything the menu bar, popover and windows show, computed off the main thread.
public struct UsageReport: Sendable {
    public var generatedAt: Date
    /// Priced entries, oldest first.
    public var entries: [UsageEntry] = []
    public var blocks: [UsageBlock] = []
    public var currentBlock: UsageBlock?
    /// Largest earlier 5-hour window in the last 30 days, in tokens.
    public var busiestBlockTokens = 0
    /// Largest 7 calendar days in the last 30, before the current week, in tokens.
    public var busiestWeekTokens = 0
    public var today = Totals()
    public var week = Totals()
    public var month = Totals()
    public var modelsWeek: [Slice] = []
    public var projectsToday: [Slice] = []
    public var projectNames: [String: String] = [:]
    /// Models seen without a price for their date, most used first.
    public var unpricedModels: [String] = []
    public var codex = CodexSummary()

    public init(generatedAt: Date) {
        self.generatedAt = generatedAt
    }

    public var hasClaudeData: Bool { !entries.isEmpty }

    public func projectName(_ folder: String) -> String {
        projectNames[folder] ?? ProjectName.decode(folder: folder)
    }

    public static func build(
        entries raw: [UsageEntry],
        prices: PriceBook,
        projectNames: [String: String],
        codexSessions: [CodexSession],
        codexFolderExists: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> UsageReport {
        var report = UsageReport(generatedAt: now)
        report.projectNames = projectNames

        var pricingCache: [String: ModelPricing?] = [:]
        var unpriced: [String: Int] = [:]
        report.entries = raw.map { entry in
            var entry = entry
            let pricing: ModelPricing?
            if let cached = pricingCache[entry.model] {
                pricing = cached
            } else {
                pricing = prices.pricing(for: entry.model)
                pricingCache[entry.model] = pricing
            }
            entry.cost = pricing?.period(at: entry.date)?.cost(of: entry.tokens)
            if entry.cost == nil { unpriced[ModelName.normalize(entry.model), default: 0] += entry.tokens.total }
            return entry
        }.sorted { $0.date < $1.date }
        report.unpricedModels = unpriced.sorted { $0.value > $1.value }.map(\.key)

        report.blocks = Blocks.compute(report.entries)
        report.currentBlock = Blocks.current(in: report.blocks, now: now)
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86_400)
        // The window in progress is left out, so a new record reads above 100%.
        report.busiestBlockTokens = report.blocks
            .filter { $0.end > thirtyDaysAgo && $0.id != report.currentBlock?.id }
            .map(\.tokens.total).max() ?? 0

        let startOfToday = calendar.startOfDay(for: now)
        let weekStart = now.addingTimeInterval(-7 * 86_400)
        let monthStart = calendar.dateInterval(of: .month, for: now)?.start ?? startOfToday
        var models: [String: Slice] = [:]
        var projects: [String: Slice] = [:]
        var days: [Date: Int] = [:]
        var modelIDs: [String: String] = [:]
        var day = DateInterval(start: .distantPast, duration: 0)
        for entry in report.entries {
            if entry.date >= startOfToday {
                report.today.add(entry)
                projects[entry.project, default: Slice(id: entry.project, name: report.projectName(entry.project))].totals.add(entry)
            }
            if entry.date >= weekStart {
                report.week.add(entry)
                let id = modelIDs[entry.model] ?? ModelName.normalize(entry.model)
                modelIDs[entry.model] = id
                models[id, default: Slice(id: id, name: ModelName.display(id))].totals.add(entry)
            }
            if entry.date >= monthStart { report.month.add(entry) }
            if entry.date >= thirtyDaysAgo {
                // Entries are sorted, so the calendar is asked once per day, not per entry.
                if !(entry.date >= day.start && entry.date < day.end) {
                    day = calendar.dateInterval(of: .day, for: entry.date) ?? DateInterval(start: entry.date, duration: 86_400)
                }
                days[day.start, default: 0] += entry.tokens.total
            }
        }
        report.modelsWeek = models.values.sorted { $0.totals.tokens.total > $1.totals.tokens.total }
        report.projectsToday = projects.values.sorted { $0.totals.tokens.total > $1.totals.tokens.total }

        // Busiest week: the largest sum of 7 consecutive calendar days that ended before
        // the rolling week we're in.
        var busiestWeek = 0
        let lastDay = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: weekStart)) ?? weekStart
        for day in days.keys where day <= lastDay {
            var sum = 0
            for offset in 0..<7 {
                if let d = calendar.date(byAdding: .day, value: -offset, to: day) { sum += days[d] ?? 0 }
            }
            busiestWeek = max(busiestWeek, sum)
        }
        report.busiestWeekTokens = busiestWeek

        report.codex = codexSummary(codexSessions, folderExists: codexFolderExists, now: now, calendar: calendar)
        return report
    }

    static func codexSummary(_ sessions: [CodexSession], folderExists: Bool, now: Date, calendar: Calendar) -> CodexSummary {
        var summary = CodexSummary()
        summary.folderExists = folderExists
        summary.sessionCount = sessions.count
        let today = DateInterval(start: calendar.startOfDay(for: now), end: max(now, calendar.startOfDay(for: now)))
        let week = DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
        let withTokens = sessions.filter(\.hasTokenData)
        for session in sessions where session.overlaps(today) {
            summary.sessionsToday += 1
            summary.activeToday += session.activeTime(in: today)
        }
        if !withTokens.isEmpty {
            summary.tokensToday = withTokens.reduce(0) { $0 + $1.tokens(in: today) }
            summary.tokensWeek = withTokens.reduce(0) { $0 + $1.tokens(in: week) }
        }
        summary.rateLimits = sessions.compactMap(\.rateLimits).max { $0.observedAt < $1.observedAt }
        summary.lastActivity = sessions.compactMap(\.end).max()
        return summary
    }
}

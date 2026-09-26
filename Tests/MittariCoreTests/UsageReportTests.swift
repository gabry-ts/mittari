import XCTest
@testable import MittariCore

final class UsageReportTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func entry(_ time: String, tokens: Int = 100) -> UsageEntry {
        UsageEntry(date: Timestamp.parse(time)!, model: "claude-opus-5", tokens: TokenCounts(input: tokens), project: "p", session: "s")
    }

    func testAutoLimitAndTotals() {
        let now = Timestamp.parse("2026-09-26T12:00:00Z")!
        let report = UsageReport.build(
            entries: [
                entry("2026-09-05T10:00:00Z", tokens: 3000),
                entry("2026-09-20T10:00:00Z", tokens: 5000),
                entry("2026-09-26T09:30:00Z", tokens: 1000),
                entry("2026-09-26T11:00:00Z", tokens: 1000),
            ],
            prices: .defaults, projectNames: ["p": "app"], codexSessions: [], codexFolderExists: false,
            now: now, calendar: utc
        )
        XCTAssertEqual(report.currentBlock?.tokens.total, 2000)
        XCTAssertEqual(report.busiestBlockTokens, 5000)
        XCTAssertEqual(report.today.tokens.total, 2000)
        XCTAssertEqual(report.week.tokens.total, 7000)
        // Earlier windows only: the current one can go past 100%.
        XCTAssertEqual(report.busiestWeekTokens, 3000)
        XCTAssertEqual(report.projectsToday.first?.name, "app")
        XCTAssertEqual(report.modelsWeek.first?.name, "Opus 5")
        // Opus 5 input at $5 per million.
        XCTAssertEqual(report.today.cost, 0.01, accuracy: 1e-9)
    }

    func testOldMessagesKeepTheirHistoricalPrice() throws {
        let change = try XCTUnwrap(Timestamp.parse("2026-09-01T00:00:00Z"))
        let book = PriceBook(models: [ModelPricing(id: "claude-sonnet-5", periods: [
            PricePeriod(input: 2, output: 10, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.2),
            PricePeriod(from: change, input: 3, output: 15, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.3),
        ])], lastVerified: nil)
        let tokens = TokenCounts(input: 1_000_000)
        let entries = [
            UsageEntry(date: change.addingTimeInterval(-3600), model: "claude-sonnet-5", tokens: tokens, project: "p", session: "s"),
            UsageEntry(date: change.addingTimeInterval(3600), model: "claude-sonnet-5", tokens: tokens, project: "p", session: "s"),
        ]
        let report = UsageReport.build(entries: entries, prices: book, projectNames: [:], codexSessions: [],
                                       codexFolderExists: false, now: change.addingTimeInterval(7200))
        XCTAssertEqual(report.entries.map(\.cost), [2, 3])
    }

    func testUnpricedModelsAreListed() {
        let report = UsageReport.build(
            entries: [UsageEntry(date: Date(), model: "claude-future-9", tokens: TokenCounts(output: 10), project: "p", session: "s")],
            prices: .defaults, projectNames: [:], codexSessions: [], codexFolderExists: false
        )
        XCTAssertEqual(report.unpricedModels, ["claude-future-9"])
        XCTAssertTrue(report.today.costIsPartial)
    }

    func testCodexSummaryWithAndWithoutTokens() {
        var plain = CodexLogParser(fileName: "rollout-a.jsonl")
        plain.consume(Data(#"{"timestamp":"2026-01-26T10:00:00Z","type":"session_meta","payload":{"id":"a"}}"#.utf8))
        plain.consume(Data(#"{"timestamp":"2026-01-26T10:30:00Z","type":"turn_context","payload":{}}"#.utf8))
        let now = Timestamp.parse("2026-01-26T20:00:00Z")!

        var summary = UsageReport.codexSummary([plain.session], folderExists: true, now: now, calendar: utc)
        XCTAssertEqual(summary.sessionsToday, 1)
        XCTAssertEqual(summary.activeToday, 1800)
        XCTAssertNil(summary.tokensToday)
        XCTAssertNil(summary.rateLimits)

        var counted = CodexLogParser(fileName: "rollout-b.jsonl")
        counted.consume(Data(#"{"timestamp":"2026-01-26T11:00:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":700}}}}"#.utf8))
        summary = UsageReport.codexSummary([plain.session, counted.session], folderExists: true, now: now, calendar: utc)
        XCTAssertEqual(summary.sessionsToday, 2)
        XCTAssertEqual(summary.tokensToday, 700)
    }

    func testStatsBucketsAndLongestSession() {
        let now = Timestamp.parse("2026-09-26T12:30:00Z")!
        var entries = [entry("2026-09-26T09:10:00Z"), entry("2026-09-26T11:40:00Z", tokens: 300), entry("2026-09-20T09:00:00Z")]
        entries[2].session = "other"
        let report = UsageReport.build(entries: entries, prices: .defaults, projectNames: [:], codexSessions: [],
                                       codexFolderExists: false, now: now, calendar: utc)
        let day = UsageStats(report: report, range: .day, now: now, calendar: utc)
        XCTAssertEqual(day.buckets.count, 24)
        XCTAssertEqual(day.totals.tokens.total, 400)
        XCTAssertEqual(day.peakHour?.start, Timestamp.parse("2026-09-26T11:00:00Z"))
        XCTAssertEqual(day.longestSession?.duration, 2.5 * 3600)
        XCTAssertEqual(day.blocks.count, 1)

        let month = UsageStats(report: report, range: .month, now: now, calendar: utc)
        XCTAssertEqual(month.buckets.count, 30)
        XCTAssertEqual(month.totals.tokens.total, 500)
    }

    func testLongRangesUseDaysAndWeeks() {
        let now = Timestamp.parse("2026-09-26T12:30:00Z")!
        let entries = [entry("2026-09-26T09:10:00Z"), entry("2026-06-01T10:00:00Z", tokens: 300), entry("2025-11-02T10:00:00Z", tokens: 50)]
        let report = UsageReport.build(entries: entries, prices: .defaults, projectNames: [:], codexSessions: [],
                                       codexFolderExists: false, now: now, calendar: utc)
        let quarter = UsageStats(report: report, range: .quarter, now: now, calendar: utc)
        XCTAssertEqual(quarter.buckets.count, 90)
        XCTAssertEqual(quarter.totals.tokens.total, 100)
        XCTAssertEqual(UsageStats(report: report, range: .halfYear, now: now, calendar: utc).buckets.count, 26)
        let year = UsageStats(report: report, range: .year, now: now, calendar: utc)
        XCTAssertEqual(year.buckets.count, 52)
        XCTAssertEqual(year.totals.tokens.total, 450)
        XCTAssertTrue(year.blocks.isEmpty == false)
    }
}

import XCTest
@testable import MittariCore

final class BlocksTests: XCTestCase {
    private func entry(_ time: String, tokens: Int = 100, cost: Double? = 1) -> UsageEntry {
        UsageEntry(date: Timestamp.parse(time)!, model: "claude-opus-5", tokens: TokenCounts(input: tokens),
                   project: "p", session: "s", cost: cost)
    }

    func testBlockStartsAtFlooredHourAndLastsFiveHours() {
        let blocks = Blocks.compute([
            entry("2026-09-26T09:47:00Z"),
            entry("2026-09-26T13:59:00Z"),
            entry("2026-09-26T14:00:00Z"), // exactly at the end: a new block
        ])
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].start, Timestamp.parse("2026-09-26T09:00:00Z"))
        XCTAssertEqual(blocks[0].end, Timestamp.parse("2026-09-26T14:00:00Z"))
        XCTAssertEqual(blocks[0].tokens.total, 200)
        XCTAssertEqual(blocks[1].start, Timestamp.parse("2026-09-26T14:00:00Z"))
    }

    func testOrderDoesNotMatterAndGapsSplitBlocks() {
        let blocks = Blocks.compute([
            entry("2026-09-26T20:10:00Z"),
            entry("2026-09-26T08:30:00Z"),
            entry("2026-09-26T09:15:00Z"),
        ])
        XCTAssertEqual(blocks.map(\.start), [Timestamp.parse("2026-09-26T08:00:00Z")!, Timestamp.parse("2026-09-26T20:00:00Z")!])
        XCTAssertEqual(blocks[0].messageCount, 2)
        XCTAssertEqual(blocks[0].lastActivity, Timestamp.parse("2026-09-26T09:15:00Z"))
    }

    func testCurrentBlockAndUnpricedTokens() {
        let blocks = Blocks.compute([entry("2026-09-26T10:05:00Z"), entry("2026-09-26T11:00:00Z", tokens: 50, cost: nil)])
        XCTAssertEqual(blocks[0].cost, 1)
        XCTAssertEqual(blocks[0].unpricedTokens, 50)
        XCTAssertNotNil(Blocks.current(in: blocks, now: Timestamp.parse("2026-09-26T14:59:00Z")!))
        XCTAssertNil(Blocks.current(in: blocks, now: Timestamp.parse("2026-09-26T15:00:00Z")!))
        XCTAssertNil(Blocks.current(in: [], now: Date()))
    }
}

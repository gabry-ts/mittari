import XCTest
@testable import MittariCore

final class PricingTests: XCTestCase {
    func testCostUsesEveryTokenKind() throws {
        let period = PricePeriod(input: 5, output: 25, cacheWrite5m: 6.25, cacheWrite1h: 10, cacheRead: 0.5)
        let tokens = TokenCounts(input: 1_000_000, output: 100_000, cacheWrite5m: 200_000, cacheWrite1h: 100_000, cacheRead: 2_000_000)
        // 5 + 2.5 + 1.25 + 1 + 1
        XCTAssertEqual(try XCTUnwrap(period.cost(of: tokens)), 10.75, accuracy: 1e-9)
    }

    func testMissingPriceGivesNoCostOnlyWhenNeeded() {
        let period = PricePeriod(input: 1, output: 5, cacheWrite5m: nil, cacheWrite1h: nil, cacheRead: nil)
        XCTAssertEqual(period.cost(of: TokenCounts(input: 1_000_000)), 1)
        XCTAssertNil(period.cost(of: TokenCounts(input: 10, cacheRead: 10)))
    }

    func testDefaultsMatchClaudeCodesOwnCost() throws {
        // From a real `cost-state` line: Haiku 4.5, 896 in, 17 out, reported as $0.000981.
        let cost = try XCTUnwrap(PriceBook.defaults.cost(of: TokenCounts(input: 896, output: 17), model: "claude-haiku-4-5-20251001", at: Date()))
        XCTAssertEqual(cost, 0.000981, accuracy: 1e-12)
    }

    func testModelIDsAreNormalized() {
        XCTAssertEqual(ModelName.normalize("claude-opus-5[1m]"), "claude-opus-5")
        XCTAssertEqual(ModelName.normalize("claude-haiku-4-5-20251001"), "claude-haiku-4-5")
        XCTAssertEqual(ModelName.normalize("us.anthropic.claude-sonnet-4-5-20250929-v1:0"), "claude-sonnet-4-5")
        XCTAssertEqual(ModelName.normalize("claude-opus-4-5@20251101"), "claude-opus-4-5")
        XCTAssertEqual(ModelName.display("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(ModelName.display("claude-3-5-haiku-20241022"), "Haiku 3.5")
        XCTAssertEqual(ModelName.display("claude-fable-5-1"), "Fable 5.1")
    }

    func testOpusFiveFiveIsNotPricedAsOpusFive() {
        let tokens = TokenCounts(output: 1_000_000)
        XCTAssertEqual(PriceBook.defaults.cost(of: tokens, model: "claude-opus-5-5", at: Date()), 20)
        XCTAssertEqual(PriceBook.defaults.cost(of: tokens, model: "claude-opus-5", at: Date()), 25)
        XCTAssertNil(PriceBook.defaults.cost(of: tokens, model: "claude-unknown-9", at: Date()))
    }

    func testMessagesArePricedWithThePeriodAtTheirTimestamp() throws {
        let change = try XCTUnwrap(Timestamp.parse("2026-09-01T00:00:00Z"))
        let book = PriceBook(models: [ModelPricing(id: "claude-sonnet-5", periods: [
            PricePeriod(input: 2, output: 10, cacheWrite5m: 2.5, cacheWrite1h: 4, cacheRead: 0.2),
            PricePeriod(from: change, input: 3, output: 15, cacheWrite5m: 3.75, cacheWrite1h: 6, cacheRead: 0.3),
        ])], lastVerified: nil)
        let tokens = TokenCounts(input: 1_000_000)
        XCTAssertEqual(book.cost(of: tokens, model: "claude-sonnet-5", at: change.addingTimeInterval(-1)), 2)
        XCTAssertEqual(book.cost(of: tokens, model: "claude-sonnet-5", at: change), 3)
        XCTAssertEqual(book.cost(of: tokens, model: "claude-sonnet-5", at: change.addingTimeInterval(86_400 * 30)), 3)
    }

    func testClosedPeriodLeavesLaterUsageUnpriced() throws {
        let end = try XCTUnwrap(Timestamp.parse("2026-06-01T00:00:00Z"))
        let pricing = ModelPricing(id: "m", periods: [PricePeriod(to: end, input: 1, output: 1, cacheWrite5m: 1, cacheWrite1h: 1, cacheRead: 1)])
        XCTAssertNotNil(pricing.period(at: end.addingTimeInterval(-1)))
        XCTAssertNil(pricing.period(at: end))
    }

    func testFormat() {
        XCTAssertEqual(Format.tokens(950), "950")
        XCTAssertEqual(Format.tokens(12_345), "12K")
        XCTAssertEqual(Format.tokens(4_500_000), "4.5M")
        XCTAssertEqual(Format.tokens(1_000_000), "1M")
        XCTAssertEqual(Format.cost(nil), "—")
        XCTAssertEqual(Format.cost(12.3), "$12.30")
        XCTAssertEqual(Format.cost(1234.5), "$1,235")
        XCTAssertEqual(Format.duration(6480), "1h 48m")
        XCTAssertEqual(Format.duration(30), "<1m")
    }
}

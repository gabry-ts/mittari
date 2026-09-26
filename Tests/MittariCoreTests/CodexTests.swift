import XCTest
@testable import MittariCore

final class CodexTests: XCTestCase {
    private func parse(_ lines: [String]) -> CodexSession {
        var parser = CodexLogParser(fileName: "rollout-2026-01-26T17-43-13-abc.jsonl")
        for line in lines { parser.consume(Data(line.utf8)) }
        return parser.session
    }

    private let utcDay: DateInterval = {
        DateInterval(start: Timestamp.parse("2026-01-26T00:00:00Z")!, duration: 86_400)
    }()

    func testCurrentFormatWithoutTokenCounts() {
        let session = parse([
            #"{"timestamp":"2026-01-26T16:43:13.906Z","type":"session_meta","payload":{"id":"019b","timestamp":"2026-01-26T16:43:13.880Z","cwd":"/Users/me/matcher"}}"#,
            #"{"timestamp":"2026-01-26T16:43:37.082Z","type":"event_msg","payload":{"type":"user_message","message":"hi"}}"#,
            #"{"timestamp":"2026-01-26T17:13:37.096Z","type":"turn_context","payload":{"cwd":"/Users/me/matcher"}}"#,
        ])
        XCTAssertEqual(session.id, "019b")
        XCTAssertEqual(session.cwd, "/Users/me/matcher")
        XCTAssertFalse(session.hasTokenData)
        XCTAssertEqual(session.activeTime(in: utcDay), 30 * 60 + 23.216, accuracy: 0.01)
    }

    func testEarlyFormatHeader() {
        let session = parse([
            #"{"id":"c81c","timestamp":"2025-08-08T14:38:57.803Z","instructions":null}"#,
            #"{"record_type":"state"}"#,
            #"{"type":"message","id":null,"role":"user","content":[]}"#,
        ])
        XCTAssertEqual(session.id, "c81c")
        XCTAssertEqual(session.start, Timestamp.parse("2025-08-08T14:38:57.803Z"))
        XCTAssertFalse(session.hasTokenData)
    }

    func testTokenCountsAndRateLimits() {
        let session = parse([
            #"{"timestamp":"2026-01-25T23:50:00Z","type":"session_meta","payload":{"id":"s"}}"#,
            #"{"timestamp":"2026-01-25T23:55:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"input_tokens":900,"output_tokens":100,"total_tokens":1000}}}}"#,
            #"{"timestamp":"2026-01-26T00:10:00Z","type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":12.5,"window_minutes":300,"resets_in_seconds":3600}}}}"#,
            #"{"timestamp":"2026-01-26T00:20:00Z","type":"event_msg","payload":{"type":"token_count","info":{"total_token_usage":{"total_tokens":1600}},"rate_limits":{"primary":{"used_percent":20,"window_minutes":300,"resets_at":1769392800},"secondary":{"used_percent":3}}}}"#,
        ])
        XCTAssertTrue(session.hasTokenData)
        XCTAssertEqual(session.tokens(in: utcDay), 600)
        XCTAssertEqual(session.tokens(in: DateInterval(start: .distantPast, end: .distantFuture)), 1600)
        XCTAssertEqual(session.rateLimits?.primary?.usedPercent, 20)
        XCTAssertEqual(session.rateLimits?.primary?.resetsAt, Date(timeIntervalSince1970: 1_769_392_800))
        XCTAssertEqual(session.rateLimits?.secondary?.usedPercent, 3)
        XCTAssertEqual(session.activeTime(in: utcDay), 20 * 60)
    }

    func testIgnoresGarbage() {
        let session = parse(["", "{", #"{"type":"event_msg","payload":{"type":"token_count"}}"#])
        XCTAssertFalse(session.hasTokenData)
        XCTAssertNil(session.start)
    }
}

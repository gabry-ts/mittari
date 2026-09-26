import XCTest
@testable import MittariCore

final class ClaudeLogTests: XCTestCase {
    private func line(id: String? = "msg_1", request: String? = "req_1", time: String = "2026-09-22T14:05:11.653Z",
                      model: String = "claude-opus-5", input: Int = 2, output: Int = 669, write: Int = 23748,
                      write1h: Int? = nil, read: Int = 22957, type: String = "assistant") -> Data {
        var message: [String: Any] = [
            "model": model, "role": "assistant",
            "usage": [
                "input_tokens": input, "output_tokens": output,
                "cache_creation_input_tokens": write, "cache_read_input_tokens": read,
            ] as [String: Any],
        ]
        if let id { message["id"] = id }
        if let write1h {
            var usage = message["usage"] as! [String: Any]
            usage["cache_creation"] = ["ephemeral_1h_input_tokens": write1h, "ephemeral_5m_input_tokens": write - write1h]
            message["usage"] = usage
        }
        var object: [String: Any] = [
            "type": type, "timestamp": time, "sessionId": "s1",
            "cwd": "/Users/me/code/my-app", "message": message, "isSidechain": false,
        ]
        if let request { object["requestId"] = request }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testParsesAssistantUsage() throws {
        let record = try XCTUnwrap(ClaudeLog.parse(line: line(write1h: 23000), project: "-Users-me-code-my-app"))
        XCTAssertEqual(record.key, "msg_1:req_1")
        XCTAssertEqual(record.cwd, "/Users/me/code/my-app")
        XCTAssertEqual(record.entry.tokens, TokenCounts(input: 2, output: 669, cacheWrite5m: 748, cacheWrite1h: 23000, cacheRead: 22957))
        XCTAssertEqual(record.entry.date, Timestamp.parse("2026-09-22T14:05:11.653Z"))
        XCTAssertEqual(record.entry.date.timeIntervalSince1970, 1_790_085_911.653, accuracy: 0.001)
    }

    func testCacheWritesWithoutSplitCountAsFiveMinute() throws {
        let record = try XCTUnwrap(ClaudeLog.parse(line: line(), project: "p"))
        XCTAssertEqual(record.entry.tokens.cacheWrite5m, 23748)
        XCTAssertEqual(record.entry.tokens.cacheWrite1h, 0)
    }

    func testSkipsNonAssistantAndSyntheticLines() {
        XCTAssertNil(ClaudeLog.parse(line: line(type: "user"), project: "p"))
        XCTAssertNil(ClaudeLog.parse(line: line(model: "<synthetic>"), project: "p"))
        XCTAssertNil(ClaudeLog.parse(line: line(input: 0, output: 0, write: 0, read: 0), project: "p"))
        XCTAssertNil(ClaudeLog.parse(line: Data("not json".utf8), project: "p"))
    }

    func testDeduplicatesByMessageAndRequest() {
        var ledger = UsageLedger()
        // Streamed copies of one response: output grows, the rest repeats.
        ledger.add(ClaudeLog.parse(line: line(output: 10), project: "p")!)
        ledger.add(ClaudeLog.parse(line: line(time: "2026-09-22T14:05:13.000Z", output: 669), project: "p")!)
        // The same response again in a resumed session's file.
        ledger.add(ClaudeLog.parse(line: line(output: 669), project: "p")!)
        // A different request.
        ledger.add(ClaudeLog.parse(line: line(request: "req_2"), project: "p")!)
        XCTAssertEqual(ledger.count, 2)
        let first = ledger.entries[0]
        XCTAssertEqual(first.tokens.output, 669)
        XCTAssertEqual(first.tokens.input, 2)
        XCTAssertEqual(first.date, Timestamp.parse("2026-09-22T14:05:11.653Z"))
    }

    func testEntriesWithoutIDsAreKept() {
        var ledger = UsageLedger()
        ledger.add(ClaudeLog.parse(line: line(id: nil, request: nil), project: "p")!)
        ledger.add(ClaudeLog.parse(line: line(id: nil, request: nil), project: "p")!)
        XCTAssertEqual(ledger.count, 2)
    }

    func testPruneDropsOldEntries() {
        var ledger = UsageLedger()
        ledger.add(ClaudeLog.parse(line: line(time: "2026-08-01T00:00:00Z"), project: "p")!)
        ledger.add(ClaudeLog.parse(line: line(request: "r2", time: "2026-09-20T00:00:00Z"), project: "p")!)
        ledger.prune(before: Timestamp.parse("2026-09-01T00:00:00Z")!)
        XCTAssertEqual(ledger.count, 1)
    }

    func testTimestampFormats() {
        XCTAssertEqual(Timestamp.parse("1970-01-01T00:00:00Z"), Date(timeIntervalSince1970: 0))
        XCTAssertEqual(Timestamp.parse("2024-02-29T12:00:00.5Z")?.timeIntervalSince1970, 1_709_208_000.5)
        XCTAssertEqual(Timestamp.parse("2026-01-26T17:43:13+01:00"), Timestamp.parse("2026-01-26T16:43:13Z"))
        XCTAssertNil(Timestamp.parse("yesterday"))
    }

    func testLineReaderResumesAfterPartialLine() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mittari-\(UUID().uuidString).jsonl")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("one\ntwo\nthr".utf8).write(to: url)
        var lines: [String] = []
        let offset = try XCTUnwrap(LineReader.read(url, from: 0) { lines.append(String(decoding: $0, as: UTF8.self)) })
        XCTAssertEqual(lines, ["one", "two"])
        XCTAssertEqual(offset, 8)

        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("ee\nfour\n".utf8))
        try handle.close()
        lines = []
        let next = try XCTUnwrap(LineReader.read(url, from: offset) { lines.append(String(decoding: $0, as: UTF8.self)) })
        XCTAssertEqual(lines, ["three", "four"])
        XCTAssertEqual(next, 19)
    }
}

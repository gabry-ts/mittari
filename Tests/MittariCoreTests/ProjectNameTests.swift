import XCTest
@testable import MittariCore

final class ProjectNameTests: XCTestCase {
    func testEncodeMatchesClaudeCodeFolders() {
        XCTAssertEqual(ProjectName.encode("/Users/me/cowork/partiti.app.mac"), "-Users-me-cowork-partiti-app-mac")
        XCTAssertEqual(ProjectName.encode("/Users/me/.config"), "-Users-me--config")
    }

    func testPrefersMatchingCwd() {
        let name = ProjectName.displayName(
            folder: "-Users-me-cowork-partiti-app-mac",
            cwds: ["/Users/me/cowork/partiti.app.mac/sub", "/Users/me/cowork/partiti.app.mac"]
        ) { _ in false }
        XCTAssertEqual(name, "partiti.app.mac")
    }

    func testFallsBackToFirstCwd() {
        XCTAssertEqual(ProjectName.displayName(folder: "-x-very-long-truncated", cwds: ["/a/b/tool"]) { _ in false }, "tool")
    }

    func testDecodeWalksTheFileSystem() {
        let dirs: Set<String> = ["/Users", "/Users/me", "/Users/me/code", "/Users/me/.config"]
        let exists = { dirs.contains($0) }
        XCTAssertEqual(ProjectName.decode(folder: "-Users-me-code-my-app", exists: exists), "my-app")
        XCTAssertEqual(ProjectName.decode(folder: "-Users-me--config", exists: exists), ".config")
        XCTAssertEqual(ProjectName.displayName(folder: "-Users-me-code-my-app", cwds: [], exists: exists), "my-app")
    }

    func testDecodeWithoutMatchesUsesLastPiece() {
        XCTAssertEqual(ProjectName.decode(folder: "-gone-away-project", exists: { _ in false }), "project")
    }
}

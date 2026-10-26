import XCTest
@testable import DevKeeperCore

final class AIToolVersionTests: XCTestCase {
    func testExtractsVersionFromCommonOutputs() {
        XCTAssertEqual(AIToolService.extractVersion(from: "2.1.309 (Claude Code)"), "2.1.309")
        XCTAssertEqual(AIToolService.extractVersion(from: "example v2.1.4"), "2.1.4")
        XCTAssertEqual(AIToolService.extractVersion(from: "tool 0.86.2-beta.1"), "0.86.2-beta.1")
        XCTAssertEqual(AIToolService.extractVersion(from: "ollama version is 0.40"), "0.40")
    }
    
    func testReturnsEmptyWithoutVersion() {
        XCTAssertEqual(AIToolService.extractVersion(from: "command not found"), "")
    }
}

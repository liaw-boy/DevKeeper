import XCTest
@testable import DevKeeperCore

final class GitHubRepoParsingTests: XCTestCase {
    func testParsesCommonGitHubForms() {
        let cases = [
            "https://github.com/openai/codex",
            "https://github.com/openai/codex#readme",
            "https://github.com/openai/codex/tree/main/docs",
            "git+https://github.com/openai/codex.git",
            "https://www.github.com/openai/codex.git"
        ]
        for text in cases {
            let repo = GitHubReleaseService.githubRepo(from: text)
            XCTAssertEqual(repo?.owner, "openai", text)
            XCTAssertEqual(repo?.repo, "codex", text)
        }
    }
    
    func testRejectsNonGitHubAndMalformedInput() {
        for text in [nil, "", "https://example.com/openai/codex", "https://github.com/openai", "https://github.com/../x", "https://notgithub.com/a/b"] as [String?] {
            XCTAssertNil(GitHubReleaseService.githubRepo(from: text), text ?? "nil")
        }
    }
}

final class GitHubTagVersionTests: XCTestCase {
    func testTagVersionStripsPrefixes() {
        XCTAssertEqual(GitHubReleaseService.tagVersion("rust-v0.164.0"), "0.164.0")
        XCTAssertEqual(GitHubReleaseService.tagVersion("jq-1.7.1"), "1.7.1")
        XCTAssertEqual(GitHubReleaseService.tagVersion("v5.6.3"), "5.6.3")
        XCTAssertEqual(GitHubReleaseService.tagVersion("2.60.0"), "2.60.0")
        XCTAssertNil(GitHubReleaseService.tagVersion("latest"))
    }
}

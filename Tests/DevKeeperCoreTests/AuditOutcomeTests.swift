import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DevKeeperCore

/// Answers every request with a canned status and body.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = Data()
    
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AuditOutcomeTests: XCTestCase {
    private func service(status: Int, body: String) -> SecurityService {
        StubProtocol.status = status
        StubProtocol.body = Data(body.utf8)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return SecurityService(configuration: configuration)
    }
    
    func testServerErrorIsAFailureNotACleanResult() async {
        let result = await service(status: 500, body: "{}").auditPackageChecked(name: "left-pad", version: "1.0.0", ecosystem: "npm")
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.items.isEmpty)
    }
    
    func testUnparseableBodyIsAFailure() async {
        let result = await service(status: 200, body: "not json").auditPackageChecked(name: "left-pad", version: "1.0.0", ecosystem: "npm")
        XCTAssertFalse(result.succeeded)
    }
    
    func testEmptyAnswerIsACleanResult() async {
        let result = await service(status: 200, body: "{}").auditPackageChecked(name: "left-pad", version: "1.0.0", ecosystem: "npm")
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.items.isEmpty)
    }
    
    func testVulnerabilityIsReturned() async {
        let body = #"{"vulns":[{"id":"GHSA-xxxx-yyyy-zzzz","summary":"Example","aliases":["CVE-2099-0001"]}]}"#
        let result = await service(status: 200, body: body).auditPackageChecked(name: "left-pad", version: "1.0.0", ecosystem: "npm")
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.items.first?.cveId, "CVE-2099-0001")
    }
    
    func testOutcomeMergeAddsCountsAndCompletenessFollowsFailures() {
        var outcome = AuditOutcome(checked: 3, failed: 0)
        XCTAssertTrue(outcome.isComplete)
        outcome.merge(AuditOutcome(checked: 2, failed: 1))
        XCTAssertEqual(outcome.checked, 5)
        XCTAssertEqual(outcome.failed, 1)
        XCTAssertFalse(outcome.isComplete)
    }
}

final class DatabaseServiceTests: XCTestCase {
    func testEmbeddedDatabaseIsNotARunnableService() {
        XCTAssertFalse(DatabaseService.isRunnableService("sqlite"))
        XCTAssertFalse(DatabaseService.isRunnableService("SQLite"))
        XCTAssertTrue(DatabaseService.isRunnableService("postgresql@16"))
        XCTAssertTrue(DatabaseService.isRunnableService("redis"))
    }
}

final class PyPIInfoTests: XCTestCase {
    func testParsesSummaryVersionAndHomepage() throws {
        let json = """
        {"info":{"version":"1.2.3","summary":"  A small HTTP library.  ",
        "home_page":"","project_url":"https://pypi.org/project/demo/",
        "project_urls":{"Source":"https://example.org/demo","Homepage":"https://demo.example.org"}}}
        """
        let info = try XCTUnwrap(PythonService.parsePyPIInfo(Data(json.utf8)))
        XCTAssertEqual(info.version, "1.2.3")
        XCTAssertEqual(info.summary, "A small HTTP library.")
        XCTAssertEqual(info.homepage, "https://demo.example.org")
    }
    
    func testDropsNonHttpsLinksAndEmptyText() throws {
        let json = #"{"info":{"version":"1","summary":"","home_page":"http://insecure.example.org","project_url":"javascript:alert(1)"}}"#
        let info = try XCTUnwrap(PythonService.parsePyPIInfo(Data(json.utf8)))
        XCTAssertNil(info.summary)
        XCTAssertNil(info.homepage)
    }
    
    func testCapsLongSummaryAndRejectsBadJSON() throws {
        let long = String(repeating: "a", count: 1000)
        let info = try XCTUnwrap(PythonService.parsePyPIInfo(Data(#"{"info":{"summary":"\#(long)"}}"#.utf8)))
        XCTAssertEqual(info.summary?.count, 300)
        XCTAssertNil(PythonService.parsePyPIInfo(Data("not json".utf8)))
    }
}

final class NpmRegistryInfoTests: XCTestCase {
    func testRepositoryLinkForms() {
        XCTAssertEqual(NpmService.repositoryLink(["url": "git+https://github.com/user/repo.git"]), "https://github.com/user/repo")
        XCTAssertEqual(NpmService.repositoryLink("git://github.com/user/repo.git"), "https://github.com/user/repo")
        XCTAssertEqual(NpmService.repositoryLink("github:user/repo"), "https://github.com/user/repo")
        XCTAssertEqual(NpmService.repositoryLink("user/repo"), "https://github.com/user/repo")
        XCTAssertEqual(NpmService.repositoryLink("ssh://git@github.com/user/repo.git"), "https://github.com/user/repo")
        XCTAssertNil(NpmService.repositoryLink("file:///etc/passwd"))
        XCTAssertNil(NpmService.repositoryLink("javascript:alert(1)"))
        XCTAssertNil(NpmService.repositoryLink(nil))
    }
    
    func testHomepageThenRepositoryFallback() throws {
        let withHome = #"{"version":"1.0.0","description":" demo ","homepage":"https://demo.example.org","repository":"user/repo"}"#
        let a = try XCTUnwrap(NpmService.parseRegistryInfo(Data(withHome.utf8)))
        XCTAssertEqual(a.homepage, "https://demo.example.org")
        XCTAssertEqual(a.description, "demo")
        
        let onlyRepo = #"{"version":"1.0.0","homepage":"http://insecure.example.org","repository":{"type":"git","url":"git+https://github.com/user/repo.git"}}"#
        let b = try XCTUnwrap(NpmService.parseRegistryInfo(Data(onlyRepo.utf8)))
        XCTAssertEqual(b.homepage, "https://github.com/user/repo")
        
        let empty = try XCTUnwrap(NpmService.parseRegistryInfo(Data(#"{"version":"2.0.0"}"#.utf8)))
        XCTAssertNil(empty.homepage)
        XCTAssertNil(empty.description)
        XCTAssertNil(NpmService.parseRegistryInfo(Data("nope".utf8)))
    }
}

final class UVToolParsingTests: XCTestCase {
    private let sample = """
    demo-tool v0.31.0 [extras: extra1] [with: demo-lib==2.9.1] [required: >=0.30] [latest: 0.32.2] [CPython 3.12.14]
    - demo-tool
    sample-cli v0.9.96 [CPython 3.13.15]
    - graphify
    - graphify-mcp
    ruff v0.4.0 [required: ==0.4.0] [latest: 0.17.3]
    - ruff
    """
    
    func testParsesHeadersExtrasAndExecutables() {
        let tools = UVToolService.parseList(sample)
        XCTAssertEqual(tools.map(\.name), ["demo-tool", "sample-cli", "ruff"])
        XCTAssertEqual(tools[0].version, "0.31.0")
        XCTAssertEqual(tools[0].extras, ["extra1"])
        XCTAssertEqual(tools[0].with, ["demo-lib==2.9.1"])
        XCTAssertEqual(tools[0].required, ">=0.30")
        XCTAssertEqual(tools[0].latest, "0.32.2")
        XCTAssertEqual(tools[0].python, "CPython 3.12.14")
        XCTAssertEqual(tools[1].executables, ["graphify", "graphify-mcp"])
        XCTAssertNil(tools[1].latest)
    }
    
    func testExactPinIsDetected() {
        let tools = UVToolService.parseList(sample)
        XCTAssertFalse(tools[0].isPinned)
        XCTAssertTrue(tools[2].isPinned)
        var ranged = tools[0]
        ranged.required = ">=1,<2"
        XCTAssertFalse(ranged.isPinned)
        ranged.required = ">=1,==1.5"
        XCTAssertTrue(ranged.isPinned)
    }
    
    func testIgnoresNoiseAndUnsafeNames() {
        let output = "warning: something odd\n$(touch x) v1.0\nok-tool v1.2.3\n- ok\n- orphan"
        let tools = UVToolService.parseList(output)
        XCTAssertEqual(tools.map(\.name), ["ok-tool"])
        XCTAssertEqual(tools[0].executables, ["ok", "orphan"])
        XCTAssertTrue(UVToolService.parseList("").isEmpty)
        XCTAssertTrue(UVToolService.parseList("No tools installed").isEmpty)
    }
    
    func testMergeAttachesLatestOnlyToOutdatedTools() {
        let all = UVToolService.parseList("a v1.0\n- a\nb v2.0\n- b")
        let outdated = UVToolService.parseList("b v2.0 [latest: 2.5]\n- b")
        let merged = UVToolService.merge(all: all, outdated: outdated)
        XCTAssertNil(merged[0].latest)
        XCTAssertEqual(merged[1].latest, "2.5")
    }
}

final class UVStrictNameTests: XCTestCase {
    func testStrictNameRejectsPathsAndOptions() {
        XCTAssertEqual(UVToolService.strictName("my-tool_2"), "my-tool_2")
        for bad in ["a/../../x", "a/b", "@x", "-x", "a;b", "a$(b)", "a..b", ""] {
            XCTAssertNil(UVToolService.strictName(bad), bad)
        }
    }
}

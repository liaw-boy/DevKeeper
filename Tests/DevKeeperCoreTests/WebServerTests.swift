import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import DevKeeperCore

final class WebServerTests: XCTestCase {
    private func parse(_ text: String) -> HTTPRequestParser.Result {
        HTTPRequestParser.parse(Data(text.utf8))
    }
    
    func testParsesRequestWithQueryAndLowercasesHeaders() {
        let result = parse("GET /api/audit?all=1&x=a%20b HTTP/1.1\r\nHost: 127.0.0.1:1\r\nAuthorization: Bearer t\r\n\r\n")
        guard case .request(let r) = result else { return XCTFail("expected a request") }
        XCTAssertEqual(r.method, "GET")
        XCTAssertEqual(r.path, "/api/audit")
        XCTAssertEqual(r.query, ["all": "1", "x": "a b"])
        XCTAssertEqual(r.headers["authorization"], "Bearer t")
    }
    
    func testIncompleteHeadWaitsForMore() {
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nHost: x"), .incomplete)
    }
    
    func testRejectsMalformedAndUnsupportedRequests() {
        XCTAssertEqual(parse("GARBAGE\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("GET //evil HTTP/1.1\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("get / HTTP/1.1\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("GET /a b HTTP/1.1\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("GET /%00 HTTP/1.1\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("POST / HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello"), .malformed)
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"), .malformed)
        XCTAssertEqual(parse("GET / HTTP/1.1\r\nHost: a\r\nHost: b\r\n\r\n"), .malformed)
    }
    
    func testOversizedHeadIsRejected() {
        let big = "GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPRequestParser.maxHeaderBytes + 10)
        XCTAssertEqual(parse(big), .tooLarge)
    }
    
    func testHostMustBeLoopbackOnOurPort() {
        XCTAssertTrue(RequestGuard.hostIsAllowed("127.0.0.1:8765", port: 8765))
        XCTAssertTrue(RequestGuard.hostIsAllowed("LocalHost:8765", port: 8765))
        XCTAssertFalse(RequestGuard.hostIsAllowed("evil.example:8765", port: 8765))
        XCTAssertFalse(RequestGuard.hostIsAllowed("127.0.0.1:9", port: 8765))
        XCTAssertFalse(RequestGuard.hostIsAllowed(nil, port: 8765))
    }
    
    func testGuardRequiresGetTokenAndHost() {
        let token = "secret-token"
        func request(method: String = "GET", host: String = "127.0.0.1:80", headers: [String: String] = [:], query: [String: String] = [:]) -> HTTPRequest {
            HTTPRequest(method: method, path: "/", query: query, headers: ["host": host].merging(headers) { $1 })
        }
        func status(_ r: HTTPRequest, allowQuery: Bool = false) -> Int? {
            RequestGuard.rejection(for: r, token: token, port: 80, allowQueryToken: allowQuery)?.status
        }
        XCTAssertNil(status(request(headers: ["authorization": "Bearer secret-token"])))
        XCTAssertNil(status(request(query: ["token": token]), allowQuery: true))
        XCTAssertEqual(status(request(query: ["token": token])), 403, "query tokens only count where allowed")
        XCTAssertEqual(status(request(headers: ["authorization": "Bearer nope"])), 403)
        XCTAssertEqual(status(request()), 403)
        XCTAssertEqual(status(request(host: "evil.example:80", headers: ["authorization": "Bearer secret-token"])), 403)
        XCTAssertEqual(status(request(method: "POST", headers: ["authorization": "Bearer secret-token"])), 405)
    }
    
    func testConstantTimeEqualsAndTokens() {
        XCTAssertTrue(RequestGuard.constantTimeEquals("abc", "abc"))
        XCTAssertFalse(RequestGuard.constantTimeEquals("abc", "abd"))
        XCTAssertFalse(RequestGuard.constantTimeEquals("abc", "abcd"))
        XCTAssertEqual(RequestGuard.makeToken().count, 64)
        XCTAssertNotEqual(RequestGuard.makeToken(), RequestGuard.makeToken())
    }
    
    func testJobCacheReusesRecentResult() async {
        let cache = JobCache()
        let counter = Counter()
        let first = await cache.run("k") { await counter.bump(); return Data("a".utf8) }
        let second = await cache.run("k") { await counter.bump(); return Data("b".utf8) }
        XCTAssertEqual(first, second)
        let runs = await counter.value
        XCTAssertEqual(runs, 1)
    }
    
    func testServerAnswersOnLoopbackAndEnforcesToken() async throws {
        let server = try LocalHTTPServer(port: 0)
        defer { server.stop() }
        let app = WebApp(token: "tok", port: server.port, projectsRoot: nil)
        server.start { await app.handle($0) }
        
        func fetch(_ path: String, bearer: String?, host: String? = nil) async throws -> (Int, String) {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:\(server.port)\(path)")!)
            if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
            if let host { request.setValue(host, forHTTPHeaderField: "Host") }
            let (data, response) = try await URLSession.shared.devkeeperData(for: request)
            return ((response as! HTTPURLResponse).statusCode, String(decoding: data, as: UTF8.self))
        }
        
        let page = try await fetch("/?token=tok", bearer: nil)
        XCTAssertEqual(page.0, 200)
        XCTAssertTrue(page.1.contains("DevKeeper"))
        XCTAssertFalse(page.1.contains("{{NONCE}}"))
        let denied = try await fetch("/api/python", bearer: "wrong")
        XCTAssertEqual(denied.0, 403)
        let missing = try await fetch("/nope", bearer: "tok")
        XCTAssertEqual(missing.0, 404)
    }
}

private actor Counter {
    private(set) var value = 0
    func bump() { value += 1 }
}

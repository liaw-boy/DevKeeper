import Foundation

/// Read-only local web interface: one HTML page plus JSON endpoints backed by `ReportBuilder`.
public final class WebApp: Sendable {
    private let token: String
    private let port: UInt16
    private let projectsRoot: String?
    private let jobs = JobCache()
    
    public init(token: String, port: UInt16, projectsRoot: String?) {
        self.token = token
        self.port = port
        self.projectsRoot = projectsRoot
    }
    
    public func handle(_ request: HTTPRequest) async -> HTTPResponse {
        let isPage = request.path == "/"
        if let rejection = RequestGuard.rejection(for: request, token: token, port: port, allowQueryToken: isPage) {
            return rejection
        }
        
        switch request.path {
        case "/":
            return page()
        case "/api/scan":
            return await json("scan") { await ReportBuilder.scan(await ReportBuilder.loadEnvironment()) }
        case "/api/python":
            return await json("python") { ReportBuilder.interpreterReports(await ReportBuilder.loadEnvironment().interpreters) }
        case "/api/audit":
            let showAll = request.query["all"] == "1"
            let root = projectsRoot
            return await json("audit-\(showAll)") {
                let env = await ReportBuilder.loadEnvironment()
                let result = await ReportBuilder.auditGroups(env, projectsRoot: root, showAll: showAll)
                return AuditReport(items: ReportBuilder.auditItems(result.groups), hiddenCount: result.hidden, failedLookups: result.failed)
            }
        default:
            return .text(404, "Not Found")
        }
    }
    
    private func page() -> HTTPResponse {
        let nonce = RequestGuard.makeToken().prefix(24)
        let html = WebUI.html.replacingOccurrences(of: "{{NONCE}}", with: nonce)
        let csp = "default-src 'none'; script-src 'nonce-\(nonce)'; style-src 'nonce-\(nonce)'; "
            + "connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'"
        return HTTPResponse(status: 200, headers: baseHeaders(contentType: "text/html; charset=utf-8", csp: csp), body: Data(html.utf8))
    }
    
    private func json<T: Encodable & Sendable>(_ key: String, _ build: @escaping @Sendable () async -> T) async -> HTTPResponse {
        let data: Data? = await jobs.run(key) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try? encoder.encode(await build())
        }
        guard let data else { return .text(500, "Internal Server Error") }
        return HTTPResponse(status: 200, headers: baseHeaders(contentType: "application/json; charset=utf-8", csp: "default-src 'none'"), body: data)
    }
    
    private func baseHeaders(contentType: String, csp: String) -> [String: String] {
        ["Content-Type": contentType, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
         "Referrer-Policy": "no-referrer", "Content-Security-Policy": csp]
    }
}

/// Runs each kind of scan at most once at a time and keeps the result briefly, so repeated
/// requests cannot keep spawning package-manager commands.
actor JobCache {
    private var running: [String: Task<Data?, Never>] = [:]
    private var finished: [String: (at: Date, data: Data)] = [:]
    private let ttl: TimeInterval = 10
    
    func run(_ key: String, _ work: @escaping @Sendable () async -> Data?) async -> Data? {
        if let hit = finished[key], Date().timeIntervalSince(hit.at) < ttl { return hit.data }
        if let existing = running[key] { return await existing.value }
        let task = Task { await work() }
        running[key] = task
        let value = await task.value
        running[key] = nil
        if let value { finished[key] = (Date(), value) }
        return value
    }
}

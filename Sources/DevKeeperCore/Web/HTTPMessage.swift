import Foundation

public struct HTTPRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let query: [String: String]
    /// Header names are lowercased.
    public let headers: [String: String]
    
    public init(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:]) {
        self.method = method
        self.path = path
        self.query = query
        self.headers = headers
    }
}

public struct HTTPResponse: Sendable {
    public var status: Int
    public var headers: [String: String]
    public var body: Data
    
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = headers
        self.body = body
    }
    
    static let reasons = [200: "OK", 400: "Bad Request", 403: "Forbidden", 404: "Not Found",
                          405: "Method Not Allowed", 431: "Request Header Fields Too Large", 500: "Internal Server Error"]
    
    public func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reasons[status] ?? "Unknown")\r\n"
        var all = headers
        all["Content-Length"] = String(body.count)
        all["Connection"] = "close"
        for (name, value) in all.sorted(by: { $0.key < $1.key }) { head += "\(name): \(value)\r\n" }
        head += "\r\n"
        return Data(head.utf8) + body
    }
    
    public static func text(_ status: Int, _ message: String) -> HTTPResponse {
        HTTPResponse(status: status, headers: ["Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store"],
                     body: Data(message.utf8))
    }
}

public enum HTTPRequestParser {
    public static let maxHeaderBytes = 16 * 1024
    
    public enum Result: Equatable {
        case incomplete
        case malformed
        case tooLarge
        case request(HTTPRequest)
    }
    
    /// Parses the head of a request. Only bodiless requests are supported, so a declared body is rejected.
    public static func parse(_ data: Data) -> Result {
        let terminator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: terminator) else {
            return data.count > maxHeaderBytes ? .tooLarge : .incomplete
        }
        if end.lowerBound > maxHeaderBytes { return .tooLarge }
        guard let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8) else { return .malformed }
        
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: false)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .malformed }
        let method = String(requestLine[0])
        let target = String(requestLine[1])
        guard !method.isEmpty, method.allSatisfy({ $0.isASCII && $0.isUppercase }) else { return .malformed }
        guard target.hasPrefix("/"), !target.hasPrefix("//"), target.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else { return .malformed }
        
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":"), colon != line.startIndex else { return .malformed }
            let name = line[line.startIndex..<colon].lowercased()
            guard !name.contains(" ") else { return .malformed }
            // A repeated header that the guard relies on is ambiguous, so refuse it.
            if headers[name] != nil, ["host", "authorization", "content-length"].contains(name) { return .malformed }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        if let length = headers["content-length"], length != "0" { return .malformed }
        if headers["transfer-encoding"] != nil { return .malformed }
        
        let parts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        guard let path = String(parts[0]).removingPercentEncoding, !path.contains("\0") else { return .malformed }
        var query: [String: String] = [:]
        if parts.count == 2 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard let key = String(kv[0]).removingPercentEncoding else { return .malformed }
                let value = kv.count == 2 ? (String(kv[1]).removingPercentEncoding ?? "") : ""
                query[key] = value
            }
        }
        return .request(HTTPRequest(method: method, path: path, query: query, headers: headers))
    }
}

/// Protections for a server that only the local user may talk to.
public enum RequestGuard {
    /// Compares without returning early on the first differing byte.
    public static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<max(x.count, y.count) {
            diff |= Int(i < x.count ? x[i] : 0) ^ Int(i < y.count ? y[i] : 0)
        }
        return diff == 0
    }
    
    /// Only loopback host names on our own port are accepted, which blocks DNS rebinding.
    public static func hostIsAllowed(_ host: String?, port: UInt16) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "127.0.0.1:\(port)" || host == "localhost:\(port)"
    }
    
    public static func token(in request: HTTPRequest, allowQuery: Bool) -> String? {
        if let auth = request.headers["authorization"], auth.hasPrefix("Bearer ") {
            return String(auth.dropFirst("Bearer ".count))
        }
        return allowQuery ? request.query["token"] : nil
    }
    
    /// Returns an error response when the request must not be served, or nil when it is allowed.
    public static func rejection(for request: HTTPRequest, token: String, port: UInt16, allowQueryToken: Bool) -> HTTPResponse? {
        guard request.method == "GET" else { return .text(405, "Method Not Allowed") }
        guard hostIsAllowed(request.headers["host"], port: port) else { return .text(403, "Forbidden") }
        guard let supplied = Self.token(in: request, allowQuery: allowQueryToken),
              constantTimeEquals(supplied, token) else { return .text(403, "Forbidden") }
        return nil
    }
    
    public static func makeToken() -> String {
        var generator = SystemRandomNumberGenerator()
        return (0..<32).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &generator)) }.joined()
    }
}

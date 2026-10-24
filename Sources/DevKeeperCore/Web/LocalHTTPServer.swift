import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum LocalServerError: Error, CustomStringConvertible {
    case socket(String)
    
    public var description: String {
        switch self { case .socket(let reason): return reason }
    }
}

/// A minimal HTTP/1.1 server bound to the loopback interface only. One request per connection.
public final class LocalHTTPServer: @unchecked Sendable {
    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse
    
    public let port: UInt16
    private let listenFD: Int32
    private let queue = DispatchQueue(label: "devkeeper.http", attributes: .concurrent)
    private let lock = NSLock()
    private var active = 0
    private let maxConnections = 16
    /// The whole request head must arrive within this many seconds.
    private let requestDeadline: TimeInterval = 5
    
    /// Pass 0 to let the system pick a free port.
    public init(port requested: UInt16) throws {
        #if os(Linux)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { throw LocalServerError.socket("無法建立 socket") }
        
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requested.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F000001).bigEndian   // 127.0.0.1 only
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0 else {
            close(fd)
            throw LocalServerError.socket("無法綁定 127.0.0.1:\(requested)，連接埠可能已被使用")
        }
        guard listen(fd, 16) == 0 else { close(fd); throw LocalServerError.socket("無法開始監聽") }
        
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        self.port = UInt16(bigEndian: actual.sin_port)
        self.listenFD = fd
    }
    
    /// Starts accepting connections on a background thread and returns immediately.
    public func start(handler: @escaping Handler) {
        let fd = listenFD
        Thread.detachNewThread { [self] in
            while true {
                let client = accept(fd, nil, nil)
                if client < 0 { if errno == EINTR { continue }; break }
                serve(client, handler: handler)
            }
        }
    }
    
    public func stop() { close(listenFD) }
    
    private func serve(_ client: Int32, handler: @escaping Handler) {
        lock.lock()
        let allowed = active < maxConnections
        if allowed { active += 1 }
        lock.unlock()
        guard allowed else { close(client); return }
        
        // Short per-recv timeout; `readRequest` enforces the overall deadline so a trickling client cannot hold a slot.
        var recvTimeout = timeval(tv_sec: 1, tv_usec: 0)
        var sendTimeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &recvTimeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &sendTimeout, socklen_t(MemoryLayout<timeval>.size))
        #if os(macOS)
        var one: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        #endif
        
        queue.async { [self] in
            let request = readRequest(client)
            Task {
                let response: HTTPResponse
                switch request {
                case .request(let r): response = await handler(r)
                case .tooLarge: response = .text(431, "Request Header Fields Too Large")
                default: response = .text(400, "Bad Request")
                }
                queue.async { [self] in
                    writeAll(client, response.serialized())
                    close(client)
                    lock.lock(); active -= 1; lock.unlock()
                }
            }
        }
    }
    
    private func readRequest(_ client: Int32) -> HTTPRequestParser.Result {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(requestDeadline)
        while true {
            let count = recv(client, &buffer, buffer.count, 0)
            if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) && Date() < deadline { continue }
            if count <= 0 || Date() >= deadline { return .malformed }   // closed, failed or too slow
            data.append(buffer, count: count)
            let parsed = HTTPRequestParser.parse(data)
            if parsed != .incomplete { return parsed }
        }
    }
    
    private func writeAll(_ client: Int32, _ data: Data) {
        #if os(Linux)
        let flags = Int32(MSG_NOSIGNAL)
        #else
        let flags: Int32 = 0
        #endif
        data.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = send(client, raw.baseAddress! + sent, raw.count - sent, flags)
                if n <= 0 { return }
                sent += n
            }
        }
    }
}

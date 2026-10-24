import Foundation

public final class ShellExecutor: @unchecked Sendable {
    public static let shared = ShellExecutor()
    
    /// zsh is the macOS login shell; Linux distributions only guarantee a POSIX sh.
    private static var shellPath: String {
        #if os(Linux)
        return "/bin/sh"
        #else
        return "/bin/zsh"
        #endif
    }
    
    private let statusLock = NSLock()
    private var _lastStreamStatus: Int32?
    
    /// Exit status of the most recently finished `stream` call (nil if it never started).
    /// Valid once the stream has been fully consumed; actions are serialized by `isActionRunning`.
    public var lastStreamStatus: Int32? {
        statusLock.lock(); defer { statusLock.unlock() }
        return _lastStreamStatus
    }
    
    private func setLastStreamStatus(_ status: Int32?) {
        statusLock.lock(); _lastStreamStatus = status; statusLock.unlock()
    }
    
    /// A stream that runs nothing and reports failure, used when input validation rejects a value.
    public func rejectedStream(reason: String) -> AsyncStream<String> {
        setLastStreamStatus(1)
        return AsyncStream { continuation in
            continuation.yield("已拒絕執行：\(reason)\n")
            continuation.finish()
        }
    }
    
    // Construct standard PATH containing Homebrew, Node, and user binaries
    private var standardPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let customPaths = [
            "\(home)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.nvm/versions/node/current/bin",
            "\(home)/.local/share/fnm/current/bin",
            "\(home)/.cargo/bin",
            "\(home)/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return customPaths.joined(separator: ":")
    }
    
    public func run(command: String) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: Self.shellPath)
                
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = self.standardPath + ":" + (env["PATH"] ?? "")
                env["LANG"] = "en_US.UTF-8"
                process.environment = env
                
                // Use -l -c to source user profile or execute directly with custom PATH
                process.arguments = ["-c", command]
                
                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe
                
                do {
                    try process.run()
                    // Drain stderr concurrently so a chatty child cannot fill the pipe and deadlock.
                    let errorBox = DataBox()
                    let errorGroup = DispatchGroup()
                    errorGroup.enter()
                    DispatchQueue.global(qos: .userInitiated).async {
                        errorBox.data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        errorGroup.leave()
                    }
                    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    errorGroup.wait()
                    let errorData = errorBox.data
                    process.waitUntilExit()
                    
                    let stdoutStr = String(data: outputData, encoding: .utf8) ?? ""
                    let stderrStr = String(data: errorData, encoding: .utf8) ?? ""
                    
                    if process.terminationStatus == 0 {
                        continuation.resume(returning: stdoutStr)
                    } else {
                        // Some commands like npm list return non-zero on peer dep warnings but still provide valid json
                        if !stdoutStr.isEmpty {
                            continuation.resume(returning: stdoutStr)
                        } else {
                            let errorDesc = stderrStr.isEmpty ? "Process exited with code \(process.terminationStatus)" : stderrStr
                            continuation.resume(throwing: NSError(domain: "ShellExecutor", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: errorDesc]))
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    public func stream(command: String) -> AsyncStream<String> {
        setLastStreamStatus(nil)
        return AsyncStream { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: Self.shellPath)
                
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = self.standardPath + ":" + (env["PATH"] ?? "")
                env["LANG"] = "en_US.UTF-8"
                process.environment = env
                
                process.arguments = ["-c", command]
                
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                
                let fileHandle = pipe.fileHandleForReading
                fileHandle.readabilityHandler = { handle in
                    let data = handle.availableData
                    if data.isEmpty { return }
                    if let string = String(data: data, encoding: .utf8) {
                        continuation.yield(string)
                    }
                }
                
                do {
                    try process.run()
                    process.waitUntilExit()
                    fileHandle.readabilityHandler = nil
                    self.setLastStreamStatus(process.terminationStatus)
                    continuation.finish()
                } catch {
                    continuation.yield("執行失敗: \(error.localizedDescription)\n")
                    self.setLastStreamStatus(127)
                    fileHandle.readabilityHandler = nil
                    continuation.finish()
                }
            }
        }
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

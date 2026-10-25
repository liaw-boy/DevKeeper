import Foundation

/// Append-only record of fix attempts with the versions before and after, so an upgrade can be traced and undone.
public enum FixHistory {
    public struct Entry: Codable, Sendable, Equatable {
        public let date: Date
        public let packageName: String
        public let ecosystem: String
        public let environment: String
        public let pythonPath: String?
        public let fromVersion: String?
        public let toVersion: String?
        /// "fixed", "failed" or "rolledBack".
        public let result: String
        public let detail: String?
        
        public init(date: Date = Date(), packageName: String, ecosystem: String, environment: String, pythonPath: String?,
                    fromVersion: String?, toVersion: String?, result: String, detail: String?) {
            self.date = date
            self.packageName = packageName
            self.ecosystem = ecosystem
            self.environment = environment
            self.pythonPath = pythonPath
            self.fromVersion = fromVersion
            self.toVersion = toVersion
            self.result = result
            self.detail = detail
        }
    }
    
    /// `~/Library/Application Support/DevKeeper/fix-history.jsonl` on macOS, `~/.local/share/DevKeeper/...` on Linux.
    public static var defaultURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("DevKeeper", isDirectory: true)
            .appendingPathComponent("fix-history.jsonl")
    }
    
    private static let lock = NSLock()
    
    public static func record(_ entry: Entry, to url: URL? = defaultURL) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var data = try? encoder.encode(entry) else { return }
        data.append(0x0A)
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url)
        }
    }
    
    public static func load(from url: URL? = defaultURL) -> [Entry] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return text.split(separator: "\n").compactMap { try? decoder.decode(Entry.self, from: Data($0.utf8)) }
    }
}

import Foundation

/// Debian/Ubuntu package manager (apt). On macOS the equivalent is Homebrew.
public final class AptService: Sendable {
    public static let shared = AptService()
    
    public struct UpgradablePackage: Sendable, Hashable {
        public let name: String
        public let currentVersion: String
        public let newVersion: String
        public let suite: String
    }
    
    public func isAvailable() async -> Bool {
        let out = (try? await ShellExecutor.shared.run(command: "command -v apt-get 2>/dev/null; true")) ?? ""
        return !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Number of installed packages known to dpkg.
    public func installedCount() async -> Int {
        let out = (try? await ShellExecutor.shared.run(command: "dpkg-query -W -f='.\\n' 2>/dev/null | wc -l")) ?? ""
        return Int(out.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }
    
    /// Packages with a newer version in the already-downloaded package lists (does not run `apt update`).
    public func upgradable() async -> [UpgradablePackage] {
        let out = (try? await ShellExecutor.shared.run(command: "apt list --upgradable 2>/dev/null; true")) ?? ""
        return Self.parseUpgradable(out)
    }
    
    /// Parses `apt list --upgradable`, e.g. `curl/jammy-updates 7.81.0-1ubuntu1.18 amd64 [upgradable from: 7.81.0-1ubuntu1.16]`.
    public static func parseUpgradable(_ output: String) -> [UpgradablePackage] {
        var result: [UpgradablePackage] = []
        for raw in output.split(separator: "\n") {
            let line = String(raw)
            guard let slash = line.firstIndex(of: "/"),
                  let fromRange = line.range(of: "[upgradable from: ") else { continue }
            let name = String(line[..<slash])
            let rest = line[line.index(after: slash)...]
            let fields = rest.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count >= 2 else { continue }
            let suite = String(fields[0])
            let newVersion = String(fields[1])
            let current = line[fromRange.upperBound...].replacingOccurrences(of: "]", with: "").trimmingCharacters(in: .whitespaces)
            guard InputValidator.isValidPackageName(name) else { continue }
            result.append(UpgradablePackage(name: name, currentVersion: current, newVersion: newVersion, suite: suite))
        }
        return result
    }
}

import Foundation

/// One tool installed with `uv tool install`, as reported by `uv tool list`.
public struct UVToolInfo: Equatable, Sendable {
    public var name: String
    public var version: String
    /// Newest version uv found for this tool, when `--outdated` listed it.
    public var latest: String?
    /// The version limit the tool was installed with, e.g. `==0.4.0` or `<24`.
    public var required: String?
    public var extras: [String] = []
    public var with: [String] = []
    public var python: String?
    public var executables: [String] = []
    
    /// An exact pin: `uv tool upgrade` refuses to move it, whatever `latest` says.
    public var isPinned: Bool {
        guard let required else { return false }
        return required.split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("==") }
    }
}

/// What a scan of uv tools found. A missing uv and a failed listing are different from "no tools".
public enum UVToolScan: Equatable, Sendable {
    case notInstalled
    case failed
    /// `latestKnown` is false when the outdated lookup failed, so versions are listed without update status.
    case tools([UVToolInfo], latestKnown: Bool)
}

public final class UVToolService: Sendable {
    public static let shared = UVToolService()
    
    private static let listFlags = "--show-version-specifiers --show-python --show-extras --show-with"
    
    // MARK: Parsing
    
    /// Parses the text of `uv tool list`. uv has no JSON output for this, so the format is read line by line:
    /// `name vVERSION [extras: a, b] [with: x==1] [required: <2] [latest: 3.0] [CPython 3.12.1]`, then one
    /// `- executable` line per command the tool provides.
    public static func parseList(_ output: String) -> [UVToolInfo] {
        var tools: [UVToolInfo] = []
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("- ") {
                guard !tools.isEmpty else { continue }
                tools[tools.count - 1].executables.append(String(line.dropFirst(2)).trimmingCharacters(in: .whitespaces))
                continue
            }
            guard let tool = parseHeader(line) else { continue }
            tools.append(tool)
        }
        return tools
    }
    
    private static func parseHeader(_ line: String) -> UVToolInfo? {
        let firstBracket = line.firstIndex(of: "[") ?? line.endIndex
        let head = line[..<firstBracket].split(separator: " ", omittingEmptySubsequences: true)
        guard head.count == 2, head[1].hasPrefix("v"), head[1].count > 1 else { return nil }
        let name = String(head[0])
        guard InputValidator.isValidPackageName(name) else { return nil }
        var tool = UVToolInfo(name: name, version: String(head[1].dropFirst()))
        
        var rest = line[firstBracket...]
        while let open = rest.firstIndex(of: "["), let close = rest[open...].firstIndex(of: "]") {
            let body = rest[rest.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            rest = rest[rest.index(after: close)...]
            if let value = value(of: "extras:", in: body) {
                tool.extras = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if let value = value(of: "with:", in: body) {
                tool.with = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            } else if let value = value(of: "required:", in: body) {
                tool.required = value
            } else if let value = value(of: "latest:", in: body) {
                tool.latest = value
            } else if body.range(of: #"^[A-Za-z]+ [0-9]"#, options: .regularExpression) != nil {
                tool.python = body
            }
        }
        return tool
    }
    
    private static func value(of key: String, in body: String) -> String? {
        guard body.hasPrefix(key) else { return nil }
        let value = body.dropFirst(key.count).trimmingCharacters(in: .whitespaces)
        return value.isEmpty ? nil : value
    }
    
    /// Joins the full listing with the `--outdated` listing, which carries the `latest` versions.
    public static func merge(all: [UVToolInfo], outdated: [UVToolInfo]) -> [UVToolInfo] {
        let latest = Dictionary(outdated.compactMap { tool in tool.latest.map { (tool.name.lowercased(), $0) } },
                                uniquingKeysWith: { first, _ in first })
        return all.map { tool in
            var merged = tool
            merged.latest = latest[tool.name.lowercased()]
            return merged
        }
    }
    
    // MARK: Scanning
    
    public func scan() async -> UVToolScan {
        guard let found = try? await ShellExecutor.shared.run(command: "command -v uv"),
              !found.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .notInstalled }
        guard let listOutput = try? await ShellExecutor.shared.run(command: "uv tool list \(Self.listFlags) 2>/dev/null") else {
            return .failed
        }
        let all = Self.parseList(listOutput)
        guard let outdatedOutput = try? await ShellExecutor.shared.run(command: "uv tool list --outdated \(Self.listFlags) 2>/dev/null") else {
            return .tools(all, latestKnown: false)
        }
        return .tools(Self.merge(all: all, outdated: Self.parseList(outdatedOutput)), latestKnown: true)
    }
    
    /// Runs `uv pip check` on a tool's environment. Returns the problems found, or nil when it is consistent
    /// (or the check could not be run).
    public func dependencyProblems(name: String) async -> String? {
        guard let n = Self.strictName(name)?.lowercased().replacingOccurrences(of: "_", with: "-"),
              let output = try? await ShellExecutor.shared.run(
                command: "py=\"$(uv tool dir)/\(n)/bin/python\"; [ -x \"$py\" ] || exit 0; uv pip check --python \"$py\" 2>&1; echo \"__exit:$?\"") else { return nil }
        guard let range = output.range(of: "__exit:") else { return nil }
        let code = output[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard code != "0" else { return nil }
        let text = output[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(600))
    }
    
    // MARK: Commands
    
    /// Stricter than `InputValidator.safeName`: a plain PyPI name only, so no path separators, `..` or `@`.
    static func strictName(_ name: String) -> String? {
        guard name.range(of: #"\A[A-Za-z0-9][A-Za-z0-9._-]*\z"#, options: .regularExpression) != nil,
              !name.contains("..") else { return nil }
        return InputValidator.safeName(name)
    }
    
    public func upgradeTool(name: String) -> AsyncStream<String> {
        guard let n = Self.strictName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        return ShellExecutor.shared.stream(command: "uv tool upgrade \(n) 2>&1")
    }
    
    public func uninstallTool(name: String) -> AsyncStream<String> {
        guard let n = Self.strictName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        return ShellExecutor.shared.stream(command: "uv tool uninstall \(n) 2>&1")
    }
    
    public func installTool(name: String) -> AsyncStream<String> {
        guard let n = Self.strictName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        return ShellExecutor.shared.stream(command: "uv tool install \(n) 2>&1")
    }
}

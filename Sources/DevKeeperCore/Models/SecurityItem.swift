import Foundation

public enum VulnerabilitySeverity: String, Codable, Sendable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case unknown = "UNKNOWN"
    
    public var localizedName: String {
        switch self {
        case .critical: return "嚴重 (Critical)"
        case .high: return "高風險 (High)"
        case .medium: return "中度 (Medium)"
        case .low: return "低風險 (Low)"
        case .unknown: return "已知弱點"
        }
    }
}

/// Where a vulnerable Python package is installed.
public struct PythonEnvironmentRef: Hashable, Sendable {
    public enum Kind: String, Sendable { case interpreter, uvTool }
    public let kind: Kind
    /// Python executable of the environment (interpreter path, or the tool venv's python).
    public let pythonPath: String
    /// Tool name for uv tool environments.
    public let toolName: String?
    public let label: String
    
    public init(kind: Kind, pythonPath: String, toolName: String? = nil, label: String) {
        self.kind = kind
        self.pythonPath = pythonPath
        self.toolName = toolName
        self.label = label
    }
}

public struct VulnerabilityItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let cveId: String
    public let packageName: String
    public let ecosystem: String
    public let currentVersion: String
    public let fixedVersion: String?
    public let severity: VulnerabilitySeverity
    public let summary: String
    public let details: String
    public let advisoryUrl: String?
    /// Set when the vulnerable dependency comes from a local project rather than a global install.
    public let projectPath: String?
    /// Set for Python packages found in an interpreter or uv tool environment.
    public let environment: PythonEnvironmentRef?
    
    public init(
        id: String,
        cveId: String,
        packageName: String,
        ecosystem: String,
        currentVersion: String,
        fixedVersion: String? = nil,
        severity: VulnerabilitySeverity = .medium,
        summary: String,
        details: String,
        advisoryUrl: String? = nil,
        projectPath: String? = nil,
        environment: PythonEnvironmentRef? = nil
    ) {
        self.projectPath = projectPath
        self.environment = environment
        self.id = id
        self.cveId = cveId
        self.packageName = packageName
        self.ecosystem = ecosystem
        self.currentVersion = currentVersion
        self.fixedVersion = fixedVersion
        self.severity = severity
        self.summary = summary
        self.details = details
        self.advisoryUrl = advisoryUrl
    }
    
    /// Shell command that fixes this vulnerability, or "" when it cannot be fixed automatically.
    public var fixCommand: String {
        FixCommandBuilder.command(packageName: packageName, ecosystem: ecosystem, targetVersion: fixedVersion, projectPath: projectPath, environment: environment)
    }
    
    /// Copy of this item tagged with the environment it was found in.
    public func inEnvironment(_ env: PythonEnvironmentRef) -> VulnerabilityItem {
        VulnerabilityItem(
            id: id, cveId: cveId, packageName: packageName, ecosystem: ecosystem,
            currentVersion: currentVersion, fixedVersion: fixedVersion, severity: severity,
            summary: summary, details: details, advisoryUrl: advisoryUrl,
            projectPath: projectPath, environment: env
        )
    }
    
    public var osvUrl: URL? {
        if let url = InputValidator.httpsURL(advisoryUrl, allowedHosts: ["osv.dev"]) {
            return url
        }
        if let url = Self.osvUrl(for: id) { return url }
        return Self.osvUrl(for: cveId)
    }
    
    public static func osvUrl(for identifier: String) -> URL? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard InputValidator.fullyMatches(trimmed, pattern: #"[A-Za-z0-9._:-]{1,128}"#) else { return nil }
        return URL(string: "https://osv.dev/vulnerability/\(trimmed)")
    }
}

/// One fixable location of a package (an environment, or the single global install).
public struct FixTarget: Identifiable, Sendable {
    public var id: String { environment?.pythonPath ?? "global" }
    public let environment: PythonEnvironmentRef?
    public let currentVersion: String
    /// Shell command that fixes this location, or "" when it cannot be fixed automatically.
    public let command: String
}

/// All vulnerabilities of one package, merged across every environment it is installed in.
public struct PackageVulnerabilityGroup: Identifiable, Sendable {
    public var id: String { "\(ecosystem.lowercased()):\(packageName.lowercased()):\(projectPath ?? "")" }
    public let packageName: String
    public let ecosystem: String
    public let currentVersion: String
    public let targetSafeVersion: String?
    public let highestSeverity: VulnerabilitySeverity
    public let cveList: [String]
    public let vulnerabilities: [VulnerabilityItem]
    public let fixTargets: [FixTarget]
    
    public init(
        packageName: String,
        ecosystem: String,
        currentVersion: String,
        vulnerabilities: [VulnerabilityItem]
    ) {
        self.packageName = packageName
        self.ecosystem = ecosystem
        
        // Deduplicate vulnerabilities by cveId
        var uniqueVulns: [VulnerabilityItem] = []
        var seenCves = Set<String>()
        for v in vulnerabilities {
            if !seenCves.contains(v.cveId) {
                seenCves.insert(v.cveId)
                uniqueVulns.append(v)
            }
        }
        self.vulnerabilities = uniqueVulns
        self.cveList = uniqueVulns.map { $0.cveId }
        
        if vulnerabilities.contains(where: { $0.severity == .critical }) {
            self.highestSeverity = .critical
        } else if vulnerabilities.contains(where: { $0.severity == .high }) {
            self.highestSeverity = .high
        } else if vulnerabilities.contains(where: { $0.severity == .medium }) {
            self.highestSeverity = .medium
        } else if vulnerabilities.contains(where: { $0.severity == .low }) {
            self.highestSeverity = .low
        } else {
            self.highestSeverity = .unknown
        }
        
        // Find the single highest safe version across all CVEs for this package
        let fixedList = vulnerabilities.compactMap { $0.fixedVersion }.filter { !$0.isEmpty }
        let target = fixedList.max(by: { a, b in a.compare(b, options: .numeric) == .orderedAscending })
        self.targetSafeVersion = target
        
        // One fix target per environment, using the full (un-deduplicated) list so no environment is lost.
        let projectPath = vulnerabilities.first?.projectPath
        var seenEnvs = Set<String>()
        var targets: [FixTarget] = []
        for v in vulnerabilities {
            let key = v.environment?.pythonPath ?? "global"
            guard seenEnvs.insert(key).inserted else { continue }
            targets.append(FixTarget(
                environment: v.environment,
                currentVersion: v.currentVersion,
                command: FixCommandBuilder.command(
                    packageName: packageName, ecosystem: ecosystem, targetVersion: target,
                    projectPath: projectPath, environment: v.environment
                )
            ))
        }
        self.fixTargets = targets
        // Lowest installed version is the one to show in the header badge.
        self.currentVersion = targets
            .map { $0.currentVersion }
            .min { $0.compare($1, options: .numeric) == .orderedAscending } ?? currentVersion
    }
    
    /// Groups vulnerabilities by package (merging environments), most severe first.
    public static func grouped(from vulnerabilities: [VulnerabilityItem]) -> [PackageVulnerabilityGroup] {
        var groups: [String: [VulnerabilityItem]] = [:]
        for v in vulnerabilities {
            let key = "\(v.ecosystem.lowercased()):\(v.packageName.lowercased()):\(v.projectPath ?? "")"
            groups[key, default: []].append(v)
        }
        func severityScore(_ s: VulnerabilitySeverity) -> Int {
            switch s {
            case .critical: return 4
            case .high: return 3
            case .medium: return 2
            case .low: return 1
            case .unknown: return 0
            }
        }
        return groups.values.map { items in
            let first = items[0]
            return PackageVulnerabilityGroup(
                packageName: first.packageName,
                ecosystem: first.ecosystem,
                currentVersion: first.currentVersion,
                vulnerabilities: items
            )
        }.sorted { a, b in
            if a.highestSeverity != b.highestSeverity {
                return severityScore(a.highestSeverity) > severityScore(b.highestSeverity)
            }
            return a.packageName < b.packageName
        }
    }
    
    /// First available fix command (used for display and copy).
    public var fixCommand: String { fixTargets.first { !$0.command.isEmpty }?.command ?? "" }
    public var fixCommands: [String] { fixTargets.map { $0.command }.filter { !$0.isEmpty } }
    
    public var projectPath: String? { vulnerabilities.first?.projectPath }
    public var environments: [PythonEnvironmentRef] { fixTargets.compactMap { $0.environment } }
    
    /// Key for per-environment state (failures, alternative fixes).
    public func key(for environment: PythonEnvironmentRef?) -> String {
        "\(id)|\(environment?.pythonPath ?? "")"
    }
}

enum FixCommandBuilder {
    static func command(packageName: String, ecosystem: String, targetVersion: String?, projectPath: String?, environment: PythonEnvironmentRef? = nil) -> String {
        // Project dependencies are not touched automatically; the app has no per-project working directory.
        guard projectPath == nil, InputValidator.isValidPackageName(packageName) else { return "" }
        let version = targetVersion.flatMap { $0.isEmpty ? nil : $0 }
        if let version, !InputValidator.isValidVersion(version) { return "" }
        
        // uv tool environments: upgrade only the vulnerable package inside the tool's venv.
        // (`uv tool upgrade` would re-resolve and upgrade the tool's whole dependency tree, which can be gigabytes.)
        if let environment, environment.kind == .uvTool {
            let python = InputValidator.shellQuoted(environment.pythonPath)
            if let version {
                return "uv pip install --python \(python) --upgrade \"\(packageName)>=\(version)\""
            }
            return "uv pip install --python \(python) --upgrade \(packageName)"
        }
        
        let eco = ecosystem.lowercased()
        if eco.contains("pypi") || eco.contains("pip") || eco.contains("python") {
            let python = environment.map { InputValidator.shellQuoted($0.pythonPath) } ?? PythonRuntime.executable
            if let version {
                return "\(python) -m pip install --upgrade \"\(packageName)>=\(version)\""
            }
            return "\(python) -m pip install --upgrade \(packageName)"
        } else if eco.contains("npm") {
            return "npm install -g \(packageName)@\(version ?? "latest")"
        } else if eco.contains("brew") {
            return "brew upgrade \(packageName)"
        }
        return ""
    }
}

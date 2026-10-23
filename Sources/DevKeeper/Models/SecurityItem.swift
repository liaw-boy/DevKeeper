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
        guard trimmed.range(of: #"^[A-Za-z0-9._:-]{1,128}$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "https://osv.dev/vulnerability/\(trimmed)")
    }
}

public struct PackageVulnerabilityGroup: Identifiable, Sendable {
    public var id: String { "\(ecosystem.lowercased()):\(packageName.lowercased()):\(projectPath ?? ""):\(environment?.pythonPath ?? "")" }
    public let packageName: String
    public let ecosystem: String
    public let currentVersion: String
    public let targetSafeVersion: String?
    public let highestSeverity: VulnerabilitySeverity
    public let cveList: [String]
    public let vulnerabilities: [VulnerabilityItem]
    
    public init(
        packageName: String,
        ecosystem: String,
        currentVersion: String,
        vulnerabilities: [VulnerabilityItem]
    ) {
        self.packageName = packageName
        self.ecosystem = ecosystem
        self.currentVersion = currentVersion
        
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
        
        if uniqueVulns.contains(where: { $0.severity == .critical }) {
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
        if let maxFixed = fixedList.max(by: { a, b in
            a.compare(b, options: .numeric) == .orderedAscending
        }) {
            self.targetSafeVersion = maxFixed
        } else {
            self.targetSafeVersion = nil
        }
    }
    
    /// Shell command that fixes this package, or "" when it cannot be fixed automatically.
    public var fixCommand: String {
        FixCommandBuilder.command(packageName: packageName, ecosystem: ecosystem, targetVersion: targetSafeVersion, projectPath: projectPath, environment: environment)
    }
    
    public var projectPath: String? { vulnerabilities.first?.projectPath }
    public var environment: PythonEnvironmentRef? { vulnerabilities.first?.environment }
}

enum FixCommandBuilder {
    static func command(packageName: String, ecosystem: String, targetVersion: String?, projectPath: String?, environment: PythonEnvironmentRef? = nil) -> String {
        // Project dependencies are not touched automatically; the app has no per-project working directory.
        guard projectPath == nil, InputValidator.isValidPackageName(packageName) else { return "" }
        let version = targetVersion.flatMap { $0.isEmpty ? nil : $0 }
        if let version, !InputValidator.isValidVersion(version) { return "" }
        
        // uv tool environments are upgraded as a whole tool; pip is not installed inside them.
        if let environment, environment.kind == .uvTool {
            guard let tool = environment.toolName, InputValidator.isValidPackageName(tool) else { return "" }
            return "uv tool upgrade \(tool)"
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

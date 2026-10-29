import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Result of an audit run. A query that failed (offline, rate limited, bad response) is counted instead of being
/// treated as "no vulnerabilities", so callers can tell a clean result from an incomplete one.
public struct AuditOutcome: Sendable {
    public var vulnerabilities: [VulnerabilityItem] = []
    /// Package lookups attempted.
    public var checked = 0
    /// Lookups that did not get a usable answer from OSV.
    public var failed = 0
    
    public init(vulnerabilities: [VulnerabilityItem] = [], checked: Int = 0, failed: Int = 0) {
        self.vulnerabilities = vulnerabilities
        self.checked = checked
        self.failed = failed
    }
    
    /// True when every lookup got an answer.
    public var isComplete: Bool { failed == 0 }
    
    public mutating func merge(_ other: AuditOutcome) {
        vulnerabilities.append(contentsOf: other.vulnerabilities)
        checked += other.checked
        failed += other.failed
    }
}

public actor SecurityService {
    public static let shared = SecurityService()
    
    private let urlSession: URLSession
    private var cache: [String: [VulnerabilityItem]] = [:]
    
    public init(configuration: URLSessionConfiguration = .default) {
        configuration.timeoutIntervalForRequest = 6
        self.urlSession = URLSession(configuration: configuration)
    }
    
    public func auditPackage(name: String, version: String, ecosystem: String) async -> [VulnerabilityItem] {
        await auditPackageChecked(name: name, version: version, ecosystem: ecosystem).items
    }
    
    /// Looks one package up in OSV. `succeeded` is false when no usable answer came back, which is not the same
    /// as an answer with no vulnerabilities.
    public func auditPackageChecked(name: String, version: String, ecosystem: String) async -> (items: [VulnerabilityItem], succeeded: Bool) {
        let cacheKey = "\(ecosystem):\(name):\(version)"
        if let cached = cache[cacheKey] {
            return (cached, true)
        }
        
        guard let url = URL(string: "https://api.osv.dev/v1/query") else { return ([], false) }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "package": [
                "name": name,
                "ecosystem": ecosystem
            ],
            "version": version
        ]
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else {
            return ([], false)
        }
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await urlSession.devkeeperData(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return ([], false)
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ([], false)
            }
            // OSV answers `{}` when a package has no known vulnerabilities.
            let vulns = json["vulns"] as? [[String: Any]] ?? []
            
            var results: [VulnerabilityItem] = []
            for item in vulns {
                let id = item["id"] as? String ?? UUID().uuidString
                let summary = item["summary"] as? String ?? "未提供摘要"
                let details = item["details"] as? String ?? summary
                
                // Extract CVE alias if available
                let aliases = item["aliases"] as? [String] ?? []
                let cveId = aliases.first(where: { $0.hasPrefix("CVE-") }) ?? id
                
                // Extract Fixed version if available
                var fixedVersion: String? = nil
                if let affected = item["affected"] as? [[String: Any]] {
                    for aff in affected {
                        if let ranges = aff["ranges"] as? [[String: Any]] {
                            for r in ranges {
                                if let events = r["events"] as? [[String: Any]] {
                                    for ev in events {
                                        if let fixed = ev["fixed"] as? String {
                                            fixedVersion = fixed
                                            break
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Determine severity
                var severity: VulnerabilitySeverity = .medium
                if let dbSpecific = item["database_specific"] as? [String: Any],
                   let sevStr = dbSpecific["severity"] as? String {
                    switch sevStr.uppercased() {
                    case "CRITICAL": severity = .critical
                    case "HIGH": severity = .high
                    case "MODERATE", "MEDIUM": severity = .medium
                    case "LOW": severity = .low
                    default: severity = .medium
                    }
                }
                
                // Extract advisory URL
                var advisoryUrl: String? = nil
                if let refs = item["references"] as? [[String: Any]] {
                    for ref in refs {
                        if let u = ref["url"] as? String {
                            advisoryUrl = u
                            break
                        }
                    }
                }
                
                let vuln = VulnerabilityItem(
                    id: id,
                    cveId: cveId,
                    packageName: name,
                    ecosystem: ecosystem,
                    currentVersion: version,
                    fixedVersion: fixedVersion,
                    severity: severity,
                    summary: summary,
                    details: details,
                    advisoryUrl: advisoryUrl
                )
                results.append(vuln)
            }
            
            cache[cacheKey] = results
            return (results, true)
        } catch {
            return ([], false)
        }
    }
    
    /// Audits local web project dependencies from package.json and requirements.txt
    public func auditProjectDirectory(at url: URL) async -> [VulnerabilityItem] {
        await auditProjectDirectoryOutcome(at: url).vulnerabilities
    }
    
    /// Same as `auditProjectDirectory`, but also reports how many lookups failed.
    public func auditProjectDirectoryOutcome(at url: URL) async -> AuditOutcome {
        var foundVulns: [VulnerabilityItem] = []
        var checked = 0
        var failed = 0
        let fileManager = FileManager.default
        
        // 1. Check frontend/node dependencies in package.json
        let packageJsonUrl = url.appendingPathComponent("package.json")
        if fileManager.fileExists(atPath: packageJsonUrl.path),
           let data = try? Data(contentsOf: packageJsonUrl),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            var depsToScan: [String: String] = [:]
            if let deps = json["dependencies"] as? [String: String] {
                depsToScan.merge(deps) { _, new in new }
            }
            if let devDeps = json["devDependencies"] as? [String: String] {
                depsToScan.merge(devDeps) { _, new in new }
            }
            
            for (pkgName, rawVer) in depsToScan.prefix(35) {
                let cleanVer = rawVer.trimmingCharacters(in: CharacterSet(charactersIn: "^~>=< vV"))
                if !cleanVer.isEmpty {
                    let result = await auditPackageChecked(name: pkgName, version: cleanVer, ecosystem: "npm")
                    checked += 1
                    if !result.succeeded { failed += 1 }
                    foundVulns.append(contentsOf: result.items)
                }
            }
        }
        
        // 2. Check backend/python dependencies in requirements.txt
        let reqTxtUrl = url.appendingPathComponent("requirements.txt")
        if fileManager.fileExists(atPath: reqTxtUrl.path),
           let text = try? String(contentsOf: reqTxtUrl, encoding: .utf8) {
            let lines = text.components(separatedBy: .newlines)
            for line in lines.prefix(35) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if trimmed.contains("==") {
                    let parts = trimmed.components(separatedBy: "==")
                    if parts.count >= 2 {
                        let name = parts[0].trimmingCharacters(in: .whitespaces)
                        let ver = parts[1].trimmingCharacters(in: .whitespaces)
                        let result = await auditPackageChecked(name: name, version: ver, ecosystem: "PyPI")
                        checked += 1
                        if !result.succeeded { failed += 1 }
                        foundVulns.append(contentsOf: result.items)
                    }
                }
            }
        }
        
        let items = foundVulns.map { v in
            VulnerabilityItem(
                id: v.id, cveId: v.cveId, packageName: v.packageName, ecosystem: v.ecosystem,
                currentVersion: v.currentVersion, fixedVersion: v.fixedVersion, severity: v.severity,
                summary: v.summary, details: v.details, advisoryUrl: v.advisoryUrl,
                projectPath: url.path
            )
        }
        return AuditOutcome(vulnerabilities: items, checked: checked, failed: failed)
    }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public actor SecurityService {
    public static let shared = SecurityService()
    
    private let urlSession: URLSession
    private var cache: [String: [VulnerabilityItem]] = [:]
    
    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6
        self.urlSession = URLSession(configuration: config)
    }
    
    public func auditPackage(name: String, version: String, ecosystem: String) async -> [VulnerabilityItem] {
        let cacheKey = "\(ecosystem):\(name):\(version)"
        if let cached = cache[cacheKey] {
            return cached
        }
        
        guard let url = URL(string: "https://api.osv.dev/v1/query") else { return [] }
        
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
            return []
        }
        request.httpBody = httpBody
        
        do {
            let (data, response) = try await urlSession.devkeeperData(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let vulns = json["vulns"] as? [[String: Any]] else {
                return []
            }
            
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
            return results
        } catch {
            return []
        }
    }
    
    /// Audits local web project dependencies from package.json and requirements.txt
    public func auditProjectDirectory(at url: URL) async -> [VulnerabilityItem] {
        var foundVulns: [VulnerabilityItem] = []
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
                    let vulns = await auditPackage(name: pkgName, version: cleanVer, ecosystem: "npm")
                    foundVulns.append(contentsOf: vulns)
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
                        let vulns = await auditPackage(name: name, version: ver, ecosystem: "PyPI")
                        foundVulns.append(contentsOf: vulns)
                    }
                }
            }
        }
        
        return foundVulns.map { v in
            VulnerabilityItem(
                id: v.id, cveId: v.cveId, packageName: v.packageName, ecosystem: v.ecosystem,
                currentVersion: v.currentVersion, fixedVersion: v.fixedVersion, severity: v.severity,
                summary: v.summary, details: v.details, advisoryUrl: v.advisoryUrl,
                projectPath: url.path
            )
        }
    }
}

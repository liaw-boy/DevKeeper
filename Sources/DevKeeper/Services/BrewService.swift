import Foundation

public final class BrewService: Sendable {
    public static let shared = BrewService()
    
    // Structs for brew info --json=v2
    private struct BrewInfoRoot: Decodable {
        let formulae: [FormulaInfo]?
        let casks: [CaskInfo]?
    }
    
    private struct FormulaInfo: Decodable {
        let name: String
        let desc: String?
        let homepage: String?
        let installed: [InstalledVersion]?
        let versions: FormulaVersions?
    }
    
    private struct InstalledVersion: Decodable {
        let version: String
    }
    
    private struct FormulaVersions: Decodable {
        let stable: String?
    }
    
    private struct CaskInfo: Decodable {
        let token: String
        let name: [String]?
        let desc: String?
        let homepage: String?
        let version: String?
        let installed: String?
    }
    
    // Structs for brew outdated --json=v2
    private struct BrewOutdatedRoot: Decodable {
        let formulae: [OutdatedFormula]?
        let casks: [OutdatedCask]?
    }
    
    private struct OutdatedFormula: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
    }
    
    private struct OutdatedCask: Decodable {
        let name: String
        let installed_versions: [String]?
        let current_version: String?
    }
    
    public func fetchPackages() async throws -> [PackageItem] {
        var outdatedFormulaMap: [String: String] = [:]
        var outdatedCaskMap: [String: String] = [:]
        
        do {
            let outdatedRaw = try await ShellExecutor.shared.run(command: "brew outdated --json=v2")
            if let data = extractJsonData(from: outdatedRaw) {
                let outdatedData = try JSONDecoder().decode(BrewOutdatedRoot.self, from: data)
                if let forms = outdatedData.formulae {
                    for f in forms {
                        if let curr = f.current_version {
                            outdatedFormulaMap[f.name] = curr
                        }
                    }
                }
                if let casks = outdatedData.casks {
                    for c in casks {
                        if let curr = c.current_version {
                            outdatedCaskMap[c.name] = curr
                        }
                    }
                }
            }
        } catch {
            // Outdated query failed, continue with info
        }
        
        let infoRaw = try await ShellExecutor.shared.run(command: "brew info --json=v2 --installed")
        guard let data = extractJsonData(from: infoRaw) else {
            return []
        }
        
        let infoRoot = try JSONDecoder().decode(BrewInfoRoot.self, from: data)
        var result: [PackageItem] = []
        
        // Process Formulae
        if let formulae = infoRoot.formulae {
            for f in formulae {
                let installedVer = f.installed?.first?.version ?? f.versions?.stable ?? "Unknown"
                let latestVer = outdatedFormulaMap[f.name] ?? f.versions?.stable ?? installedVer
                let isOutdated = outdatedFormulaMap[f.name] != nil
                
                let status: UpdateStatus = isOutdated ?
                    PackageItem.computeUpdateStatus(current: installedVer, latest: latestVer) :
                    .upToDate
                
                result.append(PackageItem(
                    name: f.name,
                    currentVersion: installedVer,
                    latestVersion: latestVer,
                    type: .brewFormula,
                    status: status,
                    description: f.desc,
                    homepage: f.homepage
                ))
            }
        }
        
        // Process Casks
        if let casks = infoRoot.casks {
            for c in casks {
                let installedVer = c.installed ?? c.version ?? "Unknown"
                let latestVer = outdatedCaskMap[c.token] ?? c.version ?? installedVer
                let isOutdated = outdatedCaskMap[c.token] != nil
                
                let displayName = c.token // Use token as consistent identifier for uninstall/upgrade
                let status: UpdateStatus = isOutdated ? .updateAvailable : .upToDate
                
                result.append(PackageItem(
                    name: displayName,
                    currentVersion: installedVer,
                    latestVersion: latestVer,
                    type: .brewCask,
                    status: status,
                    description: c.desc,
                    homepage: c.homepage
                ))
            }
        }
        
        return result.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    public func upgradePackage(name: String, isCask: Bool) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = isCask ? "brew upgrade --cask \(n)" : "brew upgrade \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func upgradeAll() -> AsyncStream<String> {
        return ShellExecutor.shared.stream(command: "brew upgrade")
    }
    
    public func installPackage(name: String, isCask: Bool) -> AsyncStream<String> {
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = isCask ? "brew install --cask \(n)" : "brew install \(n)"
        return ShellExecutor.shared.stream(command: command)
    }
    
    public func cleanUninstallPackage(name: String, isCask: Bool) -> AsyncStream<String> {
        // For Casks: --zap wipes all ~/Library/Application Support, Preferences, Caches
        // For Formulae: autoremove cleans orphan dependencies
        guard let n = InputValidator.safeName(name) else { return ShellExecutor.shared.rejectedStream(reason: "套件名稱含不允許的字元") }
        let command = isCask ?
            "brew uninstall --zap --cask \(n)" :
            "brew uninstall \(n) ; brew autoremove"
        return ShellExecutor.shared.stream(command: command)
    }
    
    private func extractJsonData(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else {
            return nil
        }
        let jsonSubstring = text[start...end]
        return jsonSubstring.data(using: .utf8)
    }
}

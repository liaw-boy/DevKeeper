import Foundation

// Report types and builders shared by the command-line tool and the local web interface,
// so both show exactly the same data.

public struct InterpreterReport: Codable, Sendable {
    public let version: String
    public let source: String
    public let path: String
    public let supported: Bool
    public let managedByOS: Bool
    public let externallyManaged: Bool
    public let hasPip: Bool
    /// "supported", "endingSoon" or "endOfLife".
    public let supportStatus: String
    /// End-of-support date as given by `PythonLifecycle`.
    public let supportUntil: String
}

public struct UVToolReport: Codable, Sendable {
    public let name: String
    public let version: String
    public let latest: String?
    /// Installed with an exact `==` pin, so `uv tool upgrade` will not move it.
    public let pinned: Bool
    public let python: String?
}

public struct ScanReport: Codable, Sendable {
    public let os: String
    public let interpreters: [InterpreterReport]
    public let npmGlobalCount: Int
    public let npmOutdated: [String: String]
    public let pipPythonVersion: String?
    public let pipCount: Int
    public let pipOutdated: [String: String]
    public let systemPackageManager: String?
    public let systemPackageCount: Int
    public let systemUpgradable: [String]
    /// "ok", "notInstalled", "failed" or "updatesUnknown" (listed, but the newest versions could not be looked up).
    public let uvStatus: String
    public let uvTools: [UVToolReport]
}

public struct AuditItemReport: Codable, Sendable {
    public let package: String
    public let ecosystem: String
    public let environments: [String]
    public let severity: String
    public let currentVersion: String
    public let safeVersion: String?
    public let cves: [String]
    public let fixCommands: [String]
}

public struct AuditReport: Codable, Sendable {
    public let items: [AuditItemReport]
    /// Number of built-in exceptions left out (see `AuditEngine.isBuiltInException`).
    public let hiddenCount: Int
    /// Package lookups that got no answer from OSV; when above zero a clean result is not trustworthy.
    public let failedLookups: Int
}

public struct DetectedEnvironment: Sendable {
    public let interpreters: [PythonInterpreter]
    public let managers: Set<PythonSource>
}

public enum ReportBuilder {
    /// Detects interpreters and makes the automatically chosen one the current pip target.
    public static func loadEnvironment() async -> DetectedEnvironment {
        let interpreters = await PythonInterpreterService.shared.discover()
        PythonRuntime.setCurrent(InterpreterChoice.automatic(from: interpreters))
        let managers = await PythonInterpreterService.shared.availableManagers()
        return DetectedEnvironment(interpreters: interpreters, managers: managers)
    }
    
    public static func npmGlobals() async -> [(name: String, version: String)] {
        guard let items = try? await NpmService.shared.fetchInstalledPackages() else { return [] }
        return items.map { ($0.name, $0.currentVersion) }
    }
    
    public static func interpreterReports(_ interpreters: [PythonInterpreter]) -> [InterpreterReport] {
        interpreters.map { i in
            let status: String
            let until: String
            switch i.lifecycle {
            case .endOfLife(let d): status = "endOfLife"; until = "\(d)"
            case .endingSoon(let d): status = "endingSoon"; until = "\(d)"
            case .supported(let d): status = "supported"; until = "\(d)"
            }
            return InterpreterReport(
                version: i.version, source: i.source.rawValue, path: i.path,
                supported: !i.isEndOfLife, managedByOS: i.source == .system,
                externallyManaged: i.isExternallyManaged, hasPip: i.hasPip,
                supportStatus: status, supportUntil: until)
        }
    }
    
    public static func scan(_ env: DetectedEnvironment) async -> ScanReport {
        let uname = (try? await ShellExecutor.shared.run(command: "uname -sr"))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "?"
        
        let npm = await npmGlobals()
        var npmOutdated: [String: String] = [:]
        if let out = try? await ShellExecutor.shared.run(command: "npm outdated -g --json 2>/dev/null; true"),
           let start = out.firstIndex(of: "{"), let data = String(out[start...]).data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] {
            for (name, info) in json { if let latest = info["latest"] as? String { npmOutdated[name] = latest } }
        }
        
        let pipItems = (try? await PythonService.shared.fetchInstalledPackages()) ?? []
        let pipOutdated = env.interpreters.isEmpty ? [:] : await PythonService.shared.fetchOutdatedMap()
        
        var manager: String?
        var systemCount = 0
        var upgradable: [String] = []
        #if os(Linux)
        if await AptService.shared.isAvailable() {
            manager = "apt"
            systemCount = await AptService.shared.installedCount()
            upgradable = await AptService.shared.upgradable().map { "\($0.name) \($0.currentVersion) → \($0.newVersion)" }
        }
        #else
        if let out = try? await ShellExecutor.shared.run(command: "command -v brew >/dev/null 2>&1 && brew outdated --quiet; true") {
            manager = "Homebrew"
            upgradable = out.split(separator: "\n").map(String.init)
        }
        #endif
        
        var uvStatus = "ok"
        var uvTools: [UVToolReport] = []
        switch await UVToolService.shared.scan() {
        case .notInstalled: uvStatus = "notInstalled"
        case .failed: uvStatus = "failed"
        case .tools(let tools, let latestKnown):
            if !latestKnown { uvStatus = "updatesUnknown" }
            uvTools = tools.map {
                UVToolReport(name: $0.name, version: $0.version, latest: $0.latest, pinned: $0.isPinned, python: $0.python)
            }
        }
        
        return ScanReport(
            os: uname, interpreters: interpreterReports(env.interpreters),
            npmGlobalCount: npm.count, npmOutdated: npmOutdated,
            pipPythonVersion: PythonRuntime.current?.version, pipCount: pipItems.count, pipOutdated: pipOutdated,
            systemPackageManager: manager, systemPackageCount: systemCount, systemUpgradable: upgradable,
            uvStatus: uvStatus, uvTools: uvTools
        )
    }
    
    public static func auditGroups(
        _ env: DetectedEnvironment, projectsRoot: String?, showAll: Bool
    ) async -> (groups: [PackageVulnerabilityGroup], hidden: Int, failed: Int) {
        let outcome = await AuditEngine.auditOutcome(
            interpreters: env.interpreters,
            npmPackages: await npmGlobals(),
            projectsRoot: projectsRoot
        )
        let items = outcome.vulnerabilities
        let visible = showAll ? items : items.filter { !AuditEngine.isBuiltInException($0, interpreters: env.interpreters) }
        return (PackageVulnerabilityGroup.grouped(from: visible), items.count - visible.count, outcome.failed)
    }
    
    public static func auditItems(_ groups: [PackageVulnerabilityGroup]) -> [AuditItemReport] {
        groups.map {
            AuditItemReport(
                package: $0.packageName, ecosystem: $0.ecosystem,
                environments: $0.fixTargets.map { $0.environment?.label ?? "global" },
                severity: $0.highestSeverity.rawValue, currentVersion: $0.currentVersion,
                safeVersion: $0.targetSafeVersion, cves: $0.cveList, fixCommands: $0.fixCommands)
        }
    }
}

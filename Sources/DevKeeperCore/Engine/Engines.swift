import Foundation

/// Receives text produced while an engine runs (raw command output, or human-readable notices).
public typealias LogSink = @Sendable (String) async -> Void

public enum FixOutcome: Sendable {
    case fixed
    case failed(String)
}

/// Choosing which interpreter to use for what. Pure functions so the app and the CLI behave the same.
public enum InterpreterChoice {
    /// Picks a supported interpreter that pip may write to; an end-of-life one is only a last resort.
    /// `interpreters` is expected newest first (as returned by discovery).
    public static func automatic(from interpreters: [PythonInterpreter]) -> PythonInterpreter? {
        let usable = interpreters.filter { $0.hasPip }
        let supported = usable.filter { !$0.isEndOfLife }
        return supported.first { !$0.isExternallyManaged } ?? supported.first ?? usable.first
    }
    
    public static func newestSupported(from interpreters: [PythonInterpreter]) -> PythonInterpreter? {
        interpreters.first { $0.hasPip && !$0.isEndOfLife }
    }
    
    /// Python for new uv tool environments: the newest supported interpreter, or a version uv can download.
    public static func migrationTarget(from interpreters: [PythonInterpreter], uvAvailable: Bool) -> String? {
        if let path = newestSupported(from: interpreters)?.path { return path }
        return uvAvailable ? PythonLifecycle.recommendedMinor : nil
    }
}

// MARK: - Audit

public enum AuditEngine {
    /// Audits npm globals, every Python environment (interpreters and uv tool venvs) and local projects.
    public static func audit(
        interpreters: [PythonInterpreter],
        npmPackages: [(name: String, version: String)],
        projectsRoot: String?
    ) async -> [VulnerabilityItem] {
        var detected: [VulnerabilityItem] = []
        var seen = Set<String>()
        
        func record(_ vulns: [VulnerabilityItem]) {
            for v in vulns {
                let scope = v.environment?.pythonPath ?? v.projectPath ?? ""
                let key = "\(v.id)|\(v.packageName.lowercased())|\(scope)"
                if seen.insert(key).inserted { detected.append(v) }
            }
        }
        
        record(await auditList(npmPackages, ecosystem: "npm", environment: nil))
        
        for interpreter in interpreters where interpreter.hasPip {
            let env = PythonEnvironmentRef(
                kind: .interpreter, pythonPath: interpreter.path,
                label: "Python \(interpreter.version) (\(interpreter.source.rawValue))"
            )
            // Packages owned by the OS (Xcode, apt) can only be updated by the OS vendor; skip them for every
            // interpreter, because e.g. Debian's dist-packages are visible to every system python3.x.
            // Packages the user installed are still audited.
            let packages = await PythonEnvironmentService.shared.installedPackagesExcludingOSManaged(pythonPath: interpreter.path)
            record(await auditList(packages, ecosystem: "PyPI", environment: env))
        }
        for env in await PythonEnvironmentService.shared.uvToolEnvironments() {
            let packages = await PythonEnvironmentService.shared.uvToolPackages(pythonPath: env.pythonPath)
            record(await auditList(packages, ecosystem: "PyPI", environment: env))
        }
        
        if let root = projectsRoot, !root.isEmpty, FileManager.default.fileExists(atPath: root) {
            let rootURL = URL(fileURLWithPath: root)
            let subfolders = (try? FileManager.default.contentsOfDirectory(
                at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            )) ?? []
            for sub in subfolders {
                let hasPackageJson = FileManager.default.fileExists(atPath: sub.appendingPathComponent("package.json").path)
                let hasRequirements = FileManager.default.fileExists(atPath: sub.appendingPathComponent("requirements.txt").path)
                if hasPackageJson || hasRequirements {
                    record(await SecurityService.shared.auditProjectDirectory(at: sub))
                }
            }
        }
        return detected
    }
    
    /// Built-in exception: pip, setuptools and wheel inside the OS-provided Python. Users cannot upgrade that
    /// Python and the fixed versions need a newer one, so they are hidden by default.
    public static func isBuiltInException(_ v: VulnerabilityItem, interpreters: [PythonInterpreter]) -> Bool {
        guard let env = v.environment, env.kind == .interpreter,
              let interpreter = interpreters.first(where: { $0.path == env.pythonPath }),
              interpreter.source == .system else { return false }
        return PythonDependencyGraph.baseTooling.contains(PythonDependencyGraph.normalize(v.packageName))
    }
    
    /// Audits packages against OSV with a small amount of concurrency.
    static func auditList(_ packages: [(name: String, version: String)], ecosystem: String, environment: PythonEnvironmentRef?) async -> [VulnerabilityItem] {
        var results: [VulnerabilityItem] = []
        let batchSize = 8
        var index = 0
        while index < packages.count {
            let batch = Array(packages[index..<min(index + batchSize, packages.count)])
            index += batchSize
            let found = await withTaskGroup(of: [VulnerabilityItem].self) { group in
                for pkg in batch {
                    group.addTask {
                        await SecurityService.shared.auditPackage(name: pkg.name, version: pkg.version, ecosystem: ecosystem)
                    }
                }
                var all: [VulnerabilityItem] = []
                for await items in group { all.append(contentsOf: items) }
                return all
            }
            results.append(contentsOf: environment.map { env in found.map { $0.inEnvironment(env) } } ?? found)
        }
        return results
    }
}

// MARK: - Fix

public enum FixEngine {
    /// Runs a fix command, then checks the installed version instead of trusting the exit status.
    public static func execute(
        command: String,
        packageName: String,
        ecosystem: String,
        targetVersion: String?,
        environment: PythonEnvironmentRef?,
        interpreters: [PythonInterpreter],
        output: @escaping LogSink,
        notice: @escaping LogSink
    ) async -> FixOutcome {
        let eco = ecosystem.lowercased()
        let interpreter = environment.flatMap { env in interpreters.first { $0.path == env.pythonPath } }
        if environment?.kind != .uvTool, eco.contains("pypi") || eco.contains("pip") || eco.contains("python") {
            let target = interpreter ?? PythonRuntime.current
            if let target, target.isExternallyManaged {
                return .failed("Python \(target.version)（\(target.source.rawValue)）受 PEP 668 保護，不允許用 pip 直接修改。")
            }
        }
        let previous = await installedVersion(packageName: packageName, ecosystem: ecosystem, environment: environment)
        let checkCommand = DependencyCheck.command(ecosystem: ecosystem, environment: environment)
        let conflictsBefore = checkCommand == nil ? [] : await DependencyCheck.run(checkCommand!)
        
        var collected = ""
        for await chunk in ShellExecutor.shared.stream(command: command) {
            await output(chunk)
            collected += chunk
        }
        var lastStatus = ShellExecutor.shared.lastStreamStatus
        
        // The fixed version may not support this Python; try the newest compatible release as best effort.
        // Any conflict this causes is caught by the dependency check below.
        let isPip = eco.contains("pypi") || eco.contains("pip")
        if lastStatus != 0, isPip, command.contains("=="),
           collected.contains("No matching distribution") || collected.contains("Could not find a version"),
           case let fallback = FixCommandBuilder.command(packageName: packageName, ecosystem: ecosystem, targetVersion: nil,
                                                         projectPath: nil, environment: environment),
           !fallback.isEmpty {
            await notice("指定的安全版本無法安裝，改裝目前 Python 可用的最新版本：\(fallback)")
            for await chunk in ShellExecutor.shared.stream(command: fallback) {
                await output(chunk)
                collected += chunk
            }
            lastStatus = ShellExecutor.shared.lastStreamStatus
        }
        
        var installed = await installedVersion(packageName: packageName, ecosystem: ecosystem, environment: environment)
        var result = "failed"
        let outcome: FixOutcome
        
        if let checkCommand, let previous, let now = installed, now != previous,
           case let introduced = (await DependencyCheck.run(checkCommand)).subtracting(conflictsBefore), !introduced.isEmpty {
            // The upgrade broke another package's version requirement: put the old version back.
            let list = introduced.sorted().map { "• \($0)" }.joined(separator: "\n")
            let rollback = FixCommandBuilder.command(packageName: packageName, ecosystem: ecosystem, targetVersion: previous,
                                                     projectPath: nil, environment: environment)
            await notice("升級到 \(now) 會讓其他套件的版本限制不成立，正在還原為 \(previous)：\(rollback)")
            for await chunk in ShellExecutor.shared.stream(command: rollback) {
                await output(chunk)
            }
            installed = await installedVersion(packageName: packageName, ecosystem: ecosystem, environment: environment)
            if installed == previous {
                result = "rolledBack"
                outcome = .failed("其他套件限制了 \(packageName) 的版本，無法升級到安全版本，已還原為 \(previous)：\n\(list)")
            } else {
                outcome = .failed("升級後出現版本衝突，自動還原失敗，請手動執行：\(rollback)\n\(list)")
            }
        } else if let target = targetVersion, !target.isEmpty, let now = installed {
            if now.compare(target, options: .numeric) != .orderedAscending {
                result = "fixed"
                outcome = .fixed
            } else if collected.contains("Requires-Python") || collected.contains("No matching distribution") {
                let py = interpreter.map { "Python \($0.version)" } ?? "Python"
                outcome = .failed("無法修復：安全版本 \(target) 不支援目前使用的 \(py)，現有版本 \(now) 已是此環境能安裝的最新版。請改用較新的 Python 或自行升級。")
            } else {
                outcome = .failed("升級後版本為 \(now)，仍低於安全版本 \(target)。")
            }
        } else if lastStatus == 0 {
            result = "fixed"
            outcome = .fixed
        } else {
            outcome = .failed("修復指令執行失敗，請查看執行日誌。")
        }
        
        var detail: String?
        if case .failed(let reason) = outcome { detail = reason }
        FixHistory.record(FixHistory.Entry(
            packageName: packageName, ecosystem: ecosystem, environment: environment?.label ?? "全域",
            pythonPath: environment?.pythonPath, fromVersion: previous, toVersion: installed, result: result, detail: detail
        ))
        return outcome
    }
    
    public static func installedVersion(packageName: String, ecosystem: String, environment: PythonEnvironmentRef?) async -> String? {
        guard let name = InputValidator.safeName(packageName) else { return nil }
        let eco = ecosystem.lowercased()
        if let environment, environment.kind == .uvTool {
            let packages = await PythonEnvironmentService.shared.uvToolPackages(pythonPath: environment.pythonPath)
            return packages.first { PythonDependencyGraph.normalize($0.name) == PythonDependencyGraph.normalize(name) }?.version
        }
        if eco.contains("pypi") || eco.contains("pip") || eco.contains("python") {
            let python = environment.map { InputValidator.shellQuoted($0.pythonPath) } ?? PythonRuntime.executable
            guard let out = try? await ShellExecutor.shared.run(command: "\(python) -m pip show \(name)") else { return nil }
            return out.components(separatedBy: .newlines)
                .first { $0.hasPrefix("Version:") }
                .map { $0.dropFirst("Version:".count).trimmingCharacters(in: .whitespaces) }
        } else if eco.contains("npm") {
            guard let out = try? await ShellExecutor.shared.run(command: "npm ls -g \(name) --depth=0 --json"),
                  let start = out.firstIndex(of: "{"),
                  let data = String(out[start...]).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let deps = json["dependencies"] as? [String: Any],
                  let entry = deps[name] as? [String: Any] else { return nil }
            return entry["version"] as? String
        } else if eco.contains("brew") {
            guard let out = try? await ShellExecutor.shared.run(command: "brew list --versions \(name)") else { return nil }
            return out.split(separator: " ").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
}

// MARK: - Dependency check

/// Conflicts reported by `pip check` / `uv pip check`. Comparing them before and after an upgrade shows
/// whether the upgrade broke another package's version requirement.
public enum DependencyCheck {
    static func command(ecosystem: String, environment: PythonEnvironmentRef?) -> String? {
        let eco = ecosystem.lowercased()
        guard eco.contains("pypi") || eco.contains("pip") || eco.contains("python") else { return nil }
        if let environment, environment.kind == .uvTool {
            return "uv pip check --python \(InputValidator.shellQuoted(environment.pythonPath)) 2>&1"
        }
        let python = environment.map { InputValidator.shellQuoted($0.pythonPath) } ?? PythonRuntime.executable
        return "\(python) -m pip check 2>&1"
    }
    
    /// One line per broken requirement, from either pip's or uv's output format.
    public static func conflicts(in output: String) -> Set<String> {
        Set(output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.contains(" requires ") || $0.contains(" has requirement ") })
    }
    
    static func run(_ command: String) async -> Set<String> {
        conflicts(in: (try? await ShellExecutor.shared.run(command: command)) ?? "")
    }
}

// MARK: - Alternative fixes

public enum RemediationEngine {
    public enum Result: Sendable {
        case success
        case failure(String)
    }
    
    /// Installs tools into uv tool environments (when needed), then removes the old copies.
    /// Nothing is removed unless every install succeeded.
    public static func execute(
        _ plan: RemediationPlan,
        interpreters: [PythonInterpreter],
        stage: @escaping LogSink,
        output: @escaping LogSink,
        notice: @escaping LogSink
    ) async -> Result {
        guard interpreters.contains(where: { $0.path == plan.interpreterPath }) else {
            return .failure("找不到對應的 Python 環境，請重新掃描。")
        }
        let allNames = plan.toolsToInstall + plan.toolsAlreadyInUV + plan.packagesToRemove
        guard allNames.allSatisfy({ InputValidator.isValidPackageName($0) }) else {
            return .failure("套件名稱含不允許的字元，已拒絕。")
        }
        
        if plan.kind == .migrate {
            guard let target = plan.targetPython,
                  target.hasPrefix("/") || InputValidator.fullyMatches(target, pattern: #"3\.\d+"#) else {
                return .failure("沒有可用的新版 Python。")
            }
            let q = InputValidator.shellQuoted(target)
            for (i, tool) in plan.toolsToInstall.enumerated() {
                await stage("安裝 \(tool) 到獨立環境 (\(i + 1)/\(plan.toolsToInstall.count))...")
                await notice("uv tool install \(tool)（Python：\(target)）")
                for await chunk in ShellExecutor.shared.stream(command: "uv tool install --python \(q) \(tool)") {
                    await output(chunk)
                }
                let installed = await PythonEnvironmentService.shared.uvToolEnvironments()
                let ok = ShellExecutor.shared.lastStreamStatus == 0
                    && installed.contains { PythonDependencyGraph.normalize($0.toolName ?? "") == PythonDependencyGraph.normalize(tool) }
                guard ok else {
                    await notice("\(tool) 無法安裝到獨立環境，已中止，舊環境沒有任何變動。")
                    return .failure("\(tool) 無法安裝到獨立環境（可能與新版 Python 不相容），已中止，舊環境沒有任何變動。詳見執行日誌。")
                }
            }
        }
        
        await stage("移除舊環境中的 \(plan.packagesToRemove.count) 個套件...")
        let py = InputValidator.shellQuoted(plan.interpreterPath)
        let names = plan.packagesToRemove.joined(separator: " ")
        await notice("從 \(plan.interpreterLabel) 移除：\(names)")
        for await chunk in ShellExecutor.shared.stream(command: "\(py) -m pip uninstall -y \(names)") {
            await output(chunk)
        }
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            await notice("移除舊套件失敗，請查看執行日誌。")
            return .failure("新環境已就緒，但從舊環境移除套件失敗。詳見執行日誌。")
        }
        await notice("\(plan.packageName) 的修復完成（\(plan.kind == .migrate ? "已搬到獨立環境" : "已移除")）。")
        return .success
    }
}

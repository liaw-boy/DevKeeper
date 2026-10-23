import Foundation

/// A concrete way to get rid of a vulnerable package that cannot be upgraded in place.
public struct RemediationPlan: Identifiable, Sendable {
    public enum Kind: Sendable {
        /// Uninstall packages that nothing else needs.
        case remove
        /// Reinstall command-line tools into isolated `uv tool` environments, then remove the old copies.
        case migrate
    }
    
    public var id: String { "\(kind)-\(interpreterPath)-\(packageName)" }
    public let kind: Kind
    public let packageName: String
    public let interpreterPath: String
    public let interpreterLabel: String
    /// Tools to install with `uv tool install` (migrate only).
    public let toolsToInstall: [String]
    /// Tools that already have their own uv tool environment; only the old copy is removed.
    public let toolsAlreadyInUV: [String]
    /// Packages to uninstall from the old environment, including dependencies nothing else uses.
    public let packagesToRemove: [String]
    /// Python used for the new tool environments.
    public let targetPython: String?
}

/// Dependency information for one interpreter, built from `pip inspect`.
public struct PythonDependencyGraph: Sendable {
    /// Normalized name -> display name.
    public let names: [String: String]
    /// Normalized name -> normalized names it requires (installed only).
    public let requires: [String: Set<String>]
    /// Normalized name -> normalized names that require it.
    public let requiredBy: [String: Set<String>]
    
    public static func normalize(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "_", with: "-").replacingOccurrences(of: ".", with: "-")
    }
    
    public var roots: Set<String> {
        Set(names.keys.filter { (requiredBy[$0] ?? []).isEmpty && !Self.baseTooling.contains($0) })
    }
    
    /// Packages that are part of the environment itself and must never be removed.
    public static let baseTooling: Set<String> = ["pip", "setuptools", "wheel"]
    
    /// Roots that (transitively) depend on `package`, or the package itself when it is a root.
    public func owningRoots(of package: String) -> Set<String> {
        var result = Set<String>()
        var visited = Set<String>()
        var stack = [package]
        while let current = stack.popLast() {
            guard visited.insert(current).inserted else { continue }
            let parents = requiredBy[current] ?? []
            if parents.isEmpty { result.insert(current) } else { stack.append(contentsOf: parents) }
        }
        return result
    }
    
    /// Everything that can be uninstalled together with `seeds`: the seeds plus dependencies
    /// whose dependents are all being removed.
    public func removalClosure(seeds: Set<String>) -> Set<String> {
        var removed = seeds
        var changed = true
        while changed {
            changed = false
            for pkg in removed {
                for dep in requires[pkg] ?? [] where !removed.contains(dep) && !Self.baseTooling.contains(dep) {
                    if (requiredBy[dep] ?? []).isSubset(of: removed) {
                        removed.insert(dep)
                        changed = true
                    }
                }
            }
        }
        return removed
    }
}

public final class PythonEnvironmentService: Sendable {
    public static let shared = PythonEnvironmentService()
    
    private struct PipPackage: Decodable {
        let name: String
        let version: String
    }
    
    // MARK: - Package lists
    
    public func installedPackages(pythonPath: String) async -> [(name: String, version: String)] {
        let q = InputValidator.shellQuoted(pythonPath)
        guard let out = try? await ShellExecutor.shared.run(command: "\(q) -m pip list --format=json 2>/dev/null"),
              let items = decode(out) else { return [] }
        return items.map { ($0.name, $0.version) }
    }
    
    /// Packages inside a uv tool environment (these venvs do not ship pip).
    public func uvToolPackages(pythonPath: String) async -> [(name: String, version: String)] {
        let q = InputValidator.shellQuoted(pythonPath)
        guard let out = try? await ShellExecutor.shared.run(command: "uv pip list --python \(q) --format=json 2>/dev/null"),
              let items = decode(out) else { return [] }
        return items.map { ($0.name, $0.version) }
    }
    
    /// uv tool environments, each with the python executable of its venv.
    public func uvToolEnvironments() async -> [PythonEnvironmentRef] {
        guard let dirOut = try? await ShellExecutor.shared.run(command: "uv tool dir 2>/dev/null") else { return [] }
        let dir = dirOut.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else { return [] }
        let fm = FileManager.default
        let names = ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted()
        var result: [PythonEnvironmentRef] = []
        for name in names where InputValidator.isValidPackageName(name) {
            let python = "\(dir)/\(name)/bin/python"
            if fm.isExecutableFile(atPath: python) {
                result.append(PythonEnvironmentRef(kind: .uvTool, pythonPath: python, toolName: name, label: "uv tool：\(name)"))
            }
        }
        return result
    }
    
    private func decode(_ output: String) -> [PipPackage]? {
        guard let start = output.firstIndex(of: "["),
              let data = String(output[start...]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([PipPackage].self, from: data)
    }
    
    // MARK: - Dependency graph
    
    public func dependencyGraph(pythonPath: String) async -> PythonDependencyGraph? {
        let q = InputValidator.shellQuoted(pythonPath)
        guard let out = try? await ShellExecutor.shared.run(command: "\(q) -m pip inspect --quiet 2>/dev/null"),
              let start = out.firstIndex(of: "{"),
              let data = String(out[start...]).data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let installed = json["installed"] as? [[String: Any]] else { return nil }
        
        var names: [String: String] = [:]
        var rawRequires: [String: [String]] = [:]
        for entry in installed {
            guard let meta = entry["metadata"] as? [String: Any], let name = meta["name"] as? String else { continue }
            let key = PythonDependencyGraph.normalize(name)
            names[key] = name
            rawRequires[key] = (meta["requires_dist"] as? [String]) ?? []
        }
        
        var requires: [String: Set<String>] = [:]
        var requiredBy: [String: Set<String>] = [:]
        for (pkg, reqs) in rawRequires {
            for req in reqs {
                // Optional extras are not part of a normal install.
                if req.contains("extra ==") || req.contains("extra==") { continue }
                guard let range = req.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*"#, options: .regularExpression) else { continue }
                let dep = PythonDependencyGraph.normalize(String(req[range]))
                guard names[dep] != nil, dep != pkg else { continue }
                requires[pkg, default: []].insert(dep)
                requiredBy[dep, default: []].insert(pkg)
            }
        }
        return PythonDependencyGraph(names: names, requires: requires, requiredBy: requiredBy)
    }
    
    /// True when the package installs at least one command-line executable.
    public func providesExecutable(pythonPath: String, package: String) async -> Bool {
        guard let name = InputValidator.safeName(package) else { return false }
        let q = InputValidator.shellQuoted(pythonPath)
        guard let out = try? await ShellExecutor.shared.run(command: "\(q) -m pip show -f \(name) 2>/dev/null") else { return false }
        return out.split(separator: "\n").contains { line in
            let t = line.trimmingCharacters(in: .whitespaces)
            return t.range(of: #"(^|/)bin/[^/\s]+$"#, options: .regularExpression) != nil
        }
    }
    
    // MARK: - Planning
    
    public enum PlanResult: Sendable {
        case plan(RemediationPlan)
        case unavailable(String)
    }
    
    /// Works out how a vulnerable package can be removed from an interpreter without upgrading it in place.
    public func plan(packageName: String, interpreter: PythonInterpreter, targetPython: String?, uvAvailable: Bool) async -> PlanResult {
        if interpreter.isExternallyManaged {
            return .unavailable("這個 Python (\(interpreter.version)) 受 PEP 668 保護，不能直接移除套件。")
        }
        guard let graph = await dependencyGraph(pythonPath: interpreter.path) else {
            return .unavailable("無法讀取 \(interpreter.version) 的套件相依資訊（需要 pip 22.2 以上）。")
        }
        let key = PythonDependencyGraph.normalize(packageName)
        guard graph.names[key] != nil else {
            return .unavailable("在 Python \(interpreter.version) 找不到套件 \(packageName)。")
        }
        
        let label = "Python \(interpreter.version) (\(interpreter.source.rawValue))"
        let roots = graph.owningRoots(of: key)
        
        // A package nothing depends on and that has no executable is a plain library: removing it is the fix.
        if roots == [key] {
            let isTool = await providesExecutable(pythonPath: interpreter.path, package: packageName)
            if !isTool {
                let removal = graph.removalClosure(seeds: [key])
                return .plan(RemediationPlan(
                    kind: .remove, packageName: packageName, interpreterPath: interpreter.path, interpreterLabel: label,
                    toolsToInstall: [], toolsAlreadyInUV: [], packagesToRemove: displayNames(removal, graph), targetPython: nil
                ))
            }
        }
        
        // Otherwise every owning root must be a command-line tool that can live in its own environment.
        var tools: [String] = []
        var libraries: [String] = []
        for root in roots.sorted() {
            let display = graph.names[root] ?? root
            if await providesExecutable(pythonPath: interpreter.path, package: display) {
                tools.append(display)
            } else {
                libraries.append(display)
            }
        }
        guard libraries.isEmpty else {
            return .unavailable("\(packageName) 被函式庫 \(libraries.joined(separator: "、")) 使用，無法自動搬移或移除，請自行處理使用它的程式。")
        }
        guard uvAvailable else {
            return .unavailable("要把 \(tools.joined(separator: "、")) 搬到獨立環境需要 uv。請先在「偏好設定 → Python 環境」安裝 uv。")
        }
        guard let target = targetPython else {
            return .unavailable("找不到可用的新版 Python（3.10 以上）來建立獨立環境。")
        }
        let existing = Set(await uvToolEnvironments().compactMap { $0.toolName }.map { PythonDependencyGraph.normalize($0) })
        let alreadyInUV = tools.filter { existing.contains(PythonDependencyGraph.normalize($0)) }
        let toInstall = tools.filter { !existing.contains(PythonDependencyGraph.normalize($0)) }
        let removal = graph.removalClosure(seeds: Set(tools.map { PythonDependencyGraph.normalize($0) }))
        return .plan(RemediationPlan(
            kind: .migrate, packageName: packageName, interpreterPath: interpreter.path, interpreterLabel: label,
            toolsToInstall: toInstall, toolsAlreadyInUV: alreadyInUV,
            packagesToRemove: displayNames(removal, graph), targetPython: target
        ))
    }
    
    private func displayNames(_ keys: Set<String>, _ graph: PythonDependencyGraph) -> [String] {
        keys.map { graph.names[$0] ?? $0 }.sorted { $0.lowercased() < $1.lowercased() }
    }
}

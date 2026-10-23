import Foundation

public final class PythonInterpreterService: Sendable {
    public static let shared = PythonInterpreterService()
    
    private struct UVEntry: Decodable {
        let version: String
        let path: String?
        let variant: String?
        let implementation: String?
    }
    
    // MARK: - Discovery
    
    /// Finds interpreters from the system, Homebrew, pyenv and uv, de-duplicated by real path.
    public func discover() async -> [PythonInterpreter] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [(path: String, source: PythonSource)] = []
        
        // /usr/bin/python3 is a stub that pops up the "install developer tools" dialog when the
        // Command Line Tools are missing, so only touch it when they are present.
        if fm.isExecutableFile(atPath: "/usr/bin/python3"), await commandLineToolsInstalled() {
            candidates.append(("/usr/bin/python3", .system))
        }
        for dir in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let names = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
            for name in names.sorted() where name.range(of: #"^python3(\.\d+)?$"#, options: .regularExpression) != nil {
                candidates.append(("\(dir)/\(name)", .homebrew))
            }
        }
        let pyenvVersions = "\(home)/.pyenv/versions"
        for v in ((try? fm.contentsOfDirectory(atPath: pyenvVersions)) ?? []).sorted() {
            let bin = "\(pyenvVersions)/\(v)/bin/python"
            if fm.isExecutableFile(atPath: bin) { candidates.append((bin, .pyenv)) }
        }
        for entry in await uvEntries(onlyInstalled: true) {
            if let path = entry.path { candidates.append((path, .uv)) }
        }
        
        var seen = Set<String>()
        var result: [PythonInterpreter] = []
        for candidate in candidates {
            let real = URL(fileURLWithPath: candidate.path).resolvingSymlinksInPath().path
            guard !seen.contains(real) else { continue }
            if let info = await inspect(path: candidate.path, source: candidate.source) {
                seen.insert(real)
                result.append(info)
            }
        }
        return result.sorted { $0.version.compare($1.version, options: .numeric) == .orderedDescending }
    }
    
    private func commandLineToolsInstalled() async -> Bool {
        let out = (try? await ShellExecutor.shared.run(command: "xcode-select -p 2>/dev/null && echo ok")) ?? ""
        return out.contains("ok")
    }
    
    /// Which version managers exist on this machine (Homebrew, uv, pyenv).
    public func availableManagers() async -> Set<PythonSource> {
        var result = Set<PythonSource>()
        for (source, command) in [(PythonSource.homebrew, "brew"), (.uv, "uv"), (.pyenv, "pyenv")] {
            let out = (try? await ShellExecutor.shared.run(command: "command -v \(command) 2>/dev/null; true")) ?? ""
            if !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { result.insert(source) }
        }
        return result
    }
    
    private func inspect(path: String, source: PythonSource) async -> PythonInterpreter? {
        let q = InputValidator.shellQuoted(path)
        let script = "import sys,sysconfig,os;print(sys.version.split()[0]);print(os.path.exists(os.path.join(sysconfig.get_path('stdlib'),'EXTERNALLY-MANAGED')))"
        guard let out = try? await ShellExecutor.shared.run(command: "\(q) -c \(InputValidator.shellQuoted(script)) 2>/dev/null") else { return nil }
        let lines = out.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.count >= 2, InputValidator.isValidVersion(lines[0]) else { return nil }
        let pipOut = (try? await ShellExecutor.shared.run(command: "\(q) -m pip --version 2>/dev/null")) ?? ""
        return PythonInterpreter(
            path: path,
            version: lines[0],
            source: source,
            isExternallyManaged: lines[1] == "True",
            hasPip: pipOut.hasPrefix("pip ")
        )
    }
    
    private func uvEntries(onlyInstalled: Bool) async -> [UVEntry] {
        let flag = onlyInstalled ? "--only-installed " : ""
        guard let out = try? await ShellExecutor.shared.run(command: "uv python list \(flag)--output-format json 2>/dev/null"),
              let start = out.firstIndex(of: "["),
              let data = String(out[start...]).data(using: .utf8),
              let entries = try? JSONDecoder().decode([UVEntry].self, from: data) else { return [] }
        return entries.filter { $0.implementation == "cpython" && ($0.variant ?? "default") == "default" }
    }
}

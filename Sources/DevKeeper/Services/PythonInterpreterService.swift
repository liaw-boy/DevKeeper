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
        return result.sorted { compareVersions($0.version, $1.version) == .orderedDescending }
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
    
    /// Which Python the `python3` command in a terminal currently runs (path and version), if any.
    public func terminalPython() async -> (path: String, version: String)? {
        let path = ((try? await ShellExecutor.shared.run(command: "command -v python3 2>/dev/null; true")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return nil }
        let out = ((try? await ShellExecutor.shared.run(command: "\(InputValidator.shellQuoted(path)) --version 2>&1")) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (path, out.replacingOccurrences(of: "Python ", with: ""))
    }
    
    /// Makes `python`, `python3` and `python3.x` in ~/.local/bin run the given uv-managed Python.
    public func setTerminalDefaultStream(minor: String) -> AsyncStream<String> {
        guard minor.range(of: #"^3\.\d+$"#, options: .regularExpression) != nil else {
            return ShellExecutor.shared.rejectedStream(reason: "不合法的 Python 版本")
        }
        return ShellExecutor.shared.stream(command: "uv python install \(minor) --default")
    }
    
    /// Installs uv with Homebrew when available, otherwise with the official installer script.
    public func installUVStream(viaHomebrew: Bool) -> AsyncStream<String> {
        ShellExecutor.shared.stream(command: viaHomebrew
            ? "brew install uv"
            : "curl -LsSf https://astral.sh/uv/install.sh | sh")
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
    
    // MARK: - Available releases
    
    /// Releases that can be installed (not yet present) per source, one entry per minor version.
    public func installableReleases(installed: [PythonInterpreter]) async -> [PythonRelease] {
        var releases: [PythonRelease] = []
        let uvStable = await uvLatestPatches()
        // Offer only minors that are still supported, and nothing newer than the newest stable release uv knows about.
        let newestStable = uvStable.keys.max { $0.compare($1, options: .numeric) == .orderedAscending }
        func isOffered(_ minor: String) -> Bool {
            guard !PythonLifecycle.isEndOfLife(minor: minor) else { return false }
            if let newestStable, minor.compare(newestStable, options: .numeric) == .orderedDescending { return false }
            return true
        }
        let installedMinors = Dictionary(grouping: installed, by: { $0.source }).mapValues { Set($0.map { $0.minorVersion }) }
        
        // Homebrew formulae python@3.x
        if let out = try? await ShellExecutor.shared.run(command: "brew search '/^python@3\\.[0-9]+$/' 2>/dev/null") {
            for line in out.split(separator: "\n") {
                let name = line.trimmingCharacters(in: .whitespaces)
                guard let minor = brewMinor(fromFormula: name), isOffered(minor) else { continue }
                if !(installedMinors[.homebrew] ?? []).contains(minor) {
                    releases.append(PythonRelease(source: .homebrew, version: minor))
                }
            }
        }
        
        // uv: latest stable patch per minor that is not installed
        var latestPerMinor: [String: String] = [:]
        for entry in await uvEntries(onlyInstalled: false) {
            guard entry.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { continue }
            let minor = entry.version.split(separator: ".").prefix(2).joined(separator: ".")
            if let existing = latestPerMinor[minor], compareVersions(existing, entry.version) != .orderedAscending { continue }
            latestPerMinor[minor] = entry.version
        }
        for (minor, version) in latestPerMinor where isOffered(minor) && !(installedMinors[.uv] ?? []).contains(minor) {
            releases.append(PythonRelease(source: .uv, version: version))
        }
        
        // pyenv: latest stable patch per minor that is not installed
        if let out = try? await ShellExecutor.shared.run(command: "pyenv install --list 2>/dev/null") {
            var latest: [String: String] = [:]
            for line in out.split(separator: "\n") {
                let v = line.trimmingCharacters(in: .whitespaces)
                guard v.range(of: #"^3\.\d+\.\d+$"#, options: .regularExpression) != nil else { continue }
                let minor = v.split(separator: ".").prefix(2).joined(separator: ".")
                if let existing = latest[minor], compareVersions(existing, v) != .orderedAscending { continue }
                latest[minor] = v
            }
            for (minor, version) in latest where isOffered(minor) && !(installedMinors[.pyenv] ?? []).contains(minor) {
                releases.append(PythonRelease(source: .pyenv, version: version))
            }
        }
        
        return releases.sorted {
            $0.source.rawValue == $1.source.rawValue
                ? compareVersions($0.version, $1.version) == .orderedDescending
                : $0.source.rawValue < $1.source.rawValue
        }
    }
    
    /// Latest installed-minor patch offered by uv, used to tell whether a uv interpreter can be upgraded.
    public func uvLatestPatches() async -> [String: String] {
        var latest: [String: String] = [:]
        for entry in await uvEntries(onlyInstalled: false) {
            guard entry.version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { continue }
            let minor = entry.version.split(separator: ".").prefix(2).joined(separator: ".")
            if let existing = latest[minor], compareVersions(existing, entry.version) != .orderedAscending { continue }
            latest[minor] = entry.version
        }
        return latest
    }
    
    // MARK: - Install / upgrade commands
    
    public func installStream(_ release: PythonRelease) -> AsyncStream<String> {
        switch release.source {
        case .homebrew:
            guard release.version.range(of: #"^3\.\d+$"#, options: .regularExpression) != nil else {
                return ShellExecutor.shared.rejectedStream(reason: "不合法的 Python 版本")
            }
            return ShellExecutor.shared.stream(command: "brew install python@\(release.version)")
        case .uv:
            guard InputValidator.isValidVersion(release.version) else {
                return ShellExecutor.shared.rejectedStream(reason: "不合法的 Python 版本")
            }
            return ShellExecutor.shared.stream(command: "uv python install \(release.version)")
        case .pyenv:
            guard InputValidator.isValidVersion(release.version) else {
                return ShellExecutor.shared.rejectedStream(reason: "不合法的 Python 版本")
            }
            return ShellExecutor.shared.stream(command: "pyenv install -s \(release.version)")
        case .system:
            return ShellExecutor.shared.rejectedStream(reason: "系統內建的 Python 無法由 DevKeeper 安裝或升級")
        }
    }
    
    public func upgradeStream(_ interpreter: PythonInterpreter) -> AsyncStream<String> {
        let minor = interpreter.minorVersion
        guard minor.range(of: #"^3\.\d+$"#, options: .regularExpression) != nil else {
            return ShellExecutor.shared.rejectedStream(reason: "不合法的 Python 版本")
        }
        switch interpreter.source {
        case .homebrew:
            return ShellExecutor.shared.stream(command: "brew upgrade python@\(minor)")
        case .uv:
            return ShellExecutor.shared.stream(command: "uv python upgrade \(minor)")
        case .pyenv:
            // pyenv installs each patch release side by side; install the newest patch of this minor.
            return ShellExecutor.shared.stream(command: "pyenv install -s \"$(pyenv install --list | tr -d ' ' | grep -E '^\(minor.replacingOccurrences(of: ".", with: "\\."))\\.[0-9]+$' | tail -1)\"")
        case .system:
            return ShellExecutor.shared.rejectedStream(reason: "系統內建的 Python 無法由 DevKeeper 升級，請安裝新版本後改用它")
        }
    }
    
    // MARK: - Helpers
    
    private func brewMinor(fromFormula name: String) -> String? {
        guard name.range(of: #"^python@3\.\d+$"#, options: .regularExpression) != nil else { return nil }
        return String(name.dropFirst("python@".count))
    }
    
    private func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        a.compare(b, options: .numeric)
    }
}

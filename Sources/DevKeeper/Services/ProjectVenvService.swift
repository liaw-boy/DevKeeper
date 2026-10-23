import Foundation

public final class ProjectVenvService: Sendable {
    public static let shared = ProjectVenvService()
    
    private static let venvNames: Set<String> = [".venv", "venv", "env"]
    private static let skipDirs: Set<String> = ["node_modules", ".git", "site-packages", "__pycache__", ".build", "Library"]
    
    public enum RebuildResult: Sendable {
        case success(backupPath: String, versionsChanged: Bool, warnings: String)
        case failure(String)
    }
    
    // MARK: - Scan
    
    /// Finds virtual environments up to three levels below `root`.
    public func scan(root: String) -> [ProjectVenv] {
        let fm = FileManager.default
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        guard fm.fileExists(atPath: rootURL.path),
              let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: [.isDirectoryKey], options: []) else { return [] }
        
        var found: [ProjectVenv] = []
        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootURL.pathComponents.count
            let name = url.lastPathComponent
            if depth > 3 || Self.skipDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if name.contains(".old-") { enumerator.skipDescendants(); continue }
            guard Self.venvNames.contains(name) else { continue }
            let cfg = url.appendingPathComponent("pyvenv.cfg")
            guard let text = try? String(contentsOf: cfg, encoding: .utf8) else { continue }
            enumerator.skipDescendants()
            guard let version = Self.parseVersion(text) else { continue }
            let project = url.deletingLastPathComponent()
            let req = project.appendingPathComponent("requirements.txt").path
            found.append(ProjectVenv(
                projectName: project.lastPathComponent,
                projectPath: project.path,
                venvPath: url.path,
                pythonVersion: version,
                requirementsFile: fm.fileExists(atPath: req) ? req : nil
            ))
        }
        return found.sorted { $0.projectName.lowercased() < $1.projectName.lowercased() }
    }
    
    private static func parseVersion(_ cfg: String) -> String? {
        for line in cfg.split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { continue }
            if parts[0] == "version" || parts[0] == "version_info" {
                let v = parts[1].split(separator: ".").prefix(3).joined(separator: ".")
                if InputValidator.isValidVersion(v) { return v }
            }
        }
        return nil
    }
    
    // MARK: - Safety checks
    
    /// Processes currently running out of this venv (rebuilding would break them).
    /// Two signals: the command line mentions the venv (launchers such as .venv/bin/uvicorn), or a Python
    /// process runs with its working directory inside the project. On macOS the process list shows
    /// Python.app instead of the venv path, so the second signal catches `python app.py` style runs.
    /// A process started elsewhere with the venv's python and no script path cannot be detected.
    public func runningProcesses(using venv: ProjectVenv) async -> [String] {
        let out = (try? await ShellExecutor.shared.run(command: "ps -eo pid,command")) ?? ""
        let marker = venv.venvPath + "/"
        var hits: [String] = []
        var pythonPids: [(pid: Int, line: String)] = []
        for raw in out.split(separator: "\n").dropFirst() {
            let line = String(raw).trimmingCharacters(in: .whitespaces)
            guard let space = line.firstIndex(of: " "), let pid = Int(line[..<space]) else { continue }
            if line.contains(marker) { hits.append(line); continue }
            if line.lowercased().contains("python") { pythonPids.append((pid, line)) }
        }
        guard !pythonPids.isEmpty else { return hits }
        let pidList = pythonPids.map { String($0.pid) }.joined(separator: ",")
        let cwds = (try? await ShellExecutor.shared.run(command: "lsof -a -d cwd -Fpn -p \(pidList) 2>/dev/null; true")) ?? ""
        var currentPid: Int?
        for raw in cwds.split(separator: "\n") {
            if raw.hasPrefix("p") { currentPid = Int(raw.dropFirst()) }
            else if raw.hasPrefix("n"), let pid = currentPid {
                let cwd = String(raw.dropFirst())
                if cwd == venv.projectPath || cwd.hasPrefix(venv.projectPath + "/"),
                   let line = pythonPids.first(where: { $0.pid == pid })?.line {
                    hits.append(line)
                }
            }
        }
        return hits
    }
    
    // MARK: - Rebuild
    
    /// Recreates the venv with `targetPython` (e.g. "3.13") and reinstalls its packages.
    /// The old venv is moved aside first and restored automatically if anything fails.
    public func rebuild(_ venv: ProjectVenv, root: String, targetPython: String, log: @escaping @Sendable (String) -> Void) async -> RebuildResult {
        let fm = FileManager.default
        let venvURL = URL(fileURLWithPath: venv.venvPath).standardizedFileURL
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        
        // Validate: inside the projects folder, a real venv, with an expected name.
        guard venvURL.path.hasPrefix(rootURL.path + "/"),
              Self.venvNames.contains(venvURL.lastPathComponent),
              fm.fileExists(atPath: venvURL.appendingPathComponent("pyvenv.cfg").path),
              targetPython.range(of: #"^3\.\d+$"#, options: .regularExpression) != nil else {
            return .failure("環境路徑或目標版本不合法，已拒絕。")
        }
        let running = await runningProcesses(using: venv)
        guard running.isEmpty else {
            return .failure("有程式正在使用這個環境，請先停止它再重建：\n" + running.prefix(3).joined(separator: "\n"))
        }
        
        let oldPython = InputValidator.shellQuoted(venvURL.appendingPathComponent("bin/python").path)
        let work = fm.temporaryDirectory.appendingPathComponent("devkeeper-venv-\(UUID().uuidString)")
        try? fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        
        // 1. Record what is installed now.
        log("記錄目前安裝的套件...")
        let freeze = (try? await ShellExecutor.shared.run(command: "uv pip freeze --python \(oldPython) 2>/dev/null")) ?? ""
        let freezeLines = freeze.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("-e ") && !$0.contains(" @ ") }
        let freezeFile = work.appendingPathComponent("freeze.txt")
        try? freezeLines.joined(separator: "\n").write(to: freezeFile, atomically: true, encoding: .utf8)
        
        // 2. Move the old venv aside (kept as a backup; restored on failure).
        let stamp = Self.stamp()
        let backupURL = venvURL.deletingLastPathComponent().appendingPathComponent("\(venvURL.lastPathComponent).old-\(stamp)")
        do { try fm.moveItem(at: venvURL, to: backupURL) } catch { return .failure("無法備份舊環境：\(error.localizedDescription)") }
        
        func restore(_ reason: String) -> RebuildResult {
            try? fm.removeItem(at: venvURL)
            try? fm.moveItem(at: backupURL, to: venvURL)
            log("已還原舊環境。")
            return .failure(reason)
        }
        
        // 3. Create the new venv at the same path.
        log("用 Python \(targetPython) 建立新環境...")
        var createOutput = ""
        for await chunk in ShellExecutor.shared.stream(command: "uv venv --python \(targetPython) \(InputValidator.shellQuoted(venvURL.path)) 2>&1") {
            createOutput += chunk; log(chunk)
        }
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            return restore("無法建立新環境（需要網路下載 Python，或 uv 發生錯誤）。\(createOutput.suffix(200))")
        }
        
        // 4. Install packages: declared requirements first, otherwise what was installed.
        let newPython = InputValidator.shellQuoted(venvURL.appendingPathComponent("bin/python").path)
        let source = venv.requirementsFile ?? freezeFile.path
        log("安裝套件（來源：\(URL(fileURLWithPath: source).lastPathComponent)）...")
        var installOutput = ""
        for await chunk in ShellExecutor.shared.stream(command: "uv pip install --python \(newPython) -r \(InputValidator.shellQuoted(source)) 2>&1") {
            installOutput += chunk; log(chunk)
        }
        var versionsChanged = false
        if ShellExecutor.shared.lastStreamStatus != 0 {
            // Pinned versions may not support the new Python: retry with package names only.
            // Names come from the file that was actually used, so a broken requirement still fails.
            let sourceLines = ((try? String(contentsOfFile: source, encoding: .utf8)) ?? "")
                .split(separator: "\n").map(String.init)
            let names = sourceLines.compactMap { line -> String? in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") || t.hasPrefix("-") { return nil }
                guard let r = t.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*"#, options: .regularExpression) else { return nil }
                return String(t[r])
            }
            guard !names.isEmpty else { return restore("套件安裝失敗：\(installOutput.suffix(300))") }
            let namesFile = work.appendingPathComponent("names.txt")
            try? names.joined(separator: "\n").write(to: namesFile, atomically: true, encoding: .utf8)
            log("固定版本無法安裝，改裝各套件在新 Python 上的最新版本...")
            installOutput = ""
            for await chunk in ShellExecutor.shared.stream(command: "uv pip install --python \(newPython) -r \(InputValidator.shellQuoted(namesFile.path)) 2>&1") {
                installOutput += chunk; log(chunk)
            }
            guard ShellExecutor.shared.lastStreamStatus == 0 else { return restore("套件在新版 Python 上安裝失敗：\(installOutput.suffix(300))") }
            versionsChanged = true
        }
        
        // 5. Sanity check.
        let check = (try? await ShellExecutor.shared.run(command: "\(newPython) -c 'import sys; print(sys.version.split()[0])' 2>&1"))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard check.hasPrefix(targetPython) else { return restore("新環境無法執行（回報 \(check)）。") }
        let pipCheck = (try? await ShellExecutor.shared.run(command: "uv pip check --python \(newPython) 2>&1")) ?? ""
        let warnings = pipCheck.contains("Checked") && !pipCheck.contains("incompatible") ? "" : pipCheck.trimmingCharacters(in: .whitespacesAndNewlines)
        return .success(backupPath: backupURL.path, versionsChanged: versionsChanged, warnings: String(warnings.prefix(300)))
    }
    
    /// Deletes a backup created by `rebuild`. Only paths that look like a backup next to a venv are accepted.
    public func deleteBackup(_ path: String, root: String) -> Bool {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let name = url.lastPathComponent
        guard url.path.hasPrefix(URL(fileURLWithPath: root).standardizedFileURL.path + "/"),
              name.range(of: #"^(\.venv|venv|env)\.old-\d{8}-\d{6}$"#, options: .regularExpression) != nil else { return false }
        return (try? FileManager.default.removeItem(at: url)) != nil
    }
    
    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: Date())
    }
}

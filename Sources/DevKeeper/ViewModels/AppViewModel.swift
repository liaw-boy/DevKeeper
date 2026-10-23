import Foundation
import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "總覽"
    case aiTools = "AI 開發工具"
    case npm = "npm 套件"
    case python = "Python 套件"
    case pythonVersions = "Python 版本"
    case brew = "Homebrew"
    case github = "GitHub 軟體與工具"
    case database = "資料庫服務"
    case security = "安全弱點稽核"
    case console = "執行日誌"
    case settings = "偏好設定"
    
    public var id: String { rawValue }
    
    public var sfSymbol: String {
        switch self {
        case .overview: return "gauge"
        case .aiTools: return "sparkles"
        case .npm: return "cube"
        case .python: return "chevron.left.forwardslash.chevron.right"
        case .pythonVersions: return "square.stack.3d.up"
        case .brew: return "shippingbox"
        case .github: return "arrow.down.circle"
        case .database: return "cylinder.split.1x2"
        case .security: return "shield.checkered"
        case .console: return "terminal"
        case .settings: return "gearshape"
        }
    }
}

public struct SystemInfo: Sendable {
    public var osVersion: String = ""
    public var nodeVersion: String = ""
    public var npmVersion: String = ""
    public var pythonVersion: String = ""
    public var brewVersion: String = ""
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var selectedTab: NavigationTab = .overview
    @Published public var aiTools: [AIToolItem] = []
    @Published public var npmPackages: [PackageItem] = []
    @Published public var pythonPackages: [PackageItem] = []
    @Published public var brewPackages: [PackageItem] = []
    @Published public var databaseServices: [DatabaseServiceItem] = []
    @Published public var githubTools: [GitHubToolItem] = []
    @Published public var vulnerabilities: [VulnerabilityItem] = []
    
    @Published public var isScanning: Bool = false
    @Published public var isAuditingSecurity: Bool = false
    @Published public var isCheckingGitHubReleases: Bool = false
    @Published public var gitHubCheckSuccessMessage: String? = nil
    @Published public var isActionRunning: Bool = false
    @Published public var currentActionPackageId: String? = nil
    @Published public var actionProgress: Double = 0.0
    @Published public var actionStage: String = ""
    @Published public var completedPackageId: String? = nil
    @Published public var fixingVulnId: String? = nil
    @Published public var pythonInterpreters: [PythonInterpreter] = []
    @Published public var installablePythons: [PythonRelease] = []
    @Published public var uvLatestPatches: [String: String] = [:]
    @Published public var isScanningPython: Bool = false
    @Published public var pythonActionLabel: String? = nil
    @Published public var availableManagers: Set<PythonSource> = []
    @Published public var terminalPython: (path: String, version: String)? = nil
    /// Alternative fixes (remove / move to an isolated environment), keyed by vulnerability group id.
    @Published public var remediationPlans: [String: RemediationPlan] = [:]
    @Published public var remediationNotes: [String: String] = [:]
    /// Alternative fixes waiting for one confirmation after a one-click fix could not upgrade in place.
    @Published public var pendingBatch: RemediationBatch? = nil
    /// Reasons why the last fix attempt for a vulnerability group or item did not reach a safe version.
    @Published public var fixFailures: [String: String] = [:]
    @Published public var isFixingAllVulnerabilities: Bool = false
    
    @Published public var systemInfo = SystemInfo()
    @Published public var lastScanDate: Date? = nil
    @Published public var consoleLogs: [String] = []
    @Published public var liveLogOutput: String = ""
    
    // Application Version Info
    public static let appVersion: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
    }()
    public static let appBuild: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "2026.10.23"
    }()
    
    // Install Sheet control
    @Published public var showInstallSheet: Bool = false
    
    // GitHub Self-Update
    @Published public var appUpdateAvailable: Bool = false
    @Published public var latestAppVersion: String = "1.0.0"
    @Published public var appReleaseNotes: String = ""
    @Published public var appDownloadUrl: String? = nil
    
    // Background Periodic Timer (Runs every 30 minutes)
    private var backgroundTimer: Timer?
    
    public init() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.scanPythonInterpreters()
            await self.loadSystemInfo()
            await self.autoDiscoverInstalledApps()
            await self.scanAll()
            
            // Start automatic file system watcher for real-time external change detection
            FileSystemWatcher.shared.startWatching { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isActionRunning else { return }
                    self.appendLog("偵測到系統目錄變更，自動重新整理套件狀態...")
                    await self.scanAll()
                }
            }
            
            // Periodic background scan every 30 minutes (1800s)
            self.backgroundTimer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self = self, !self.isActionRunning else { return }
                    self.appendLog("執行定時背景掃描檢查 (每 30 分鐘)...")
                    await self.scanAll()
                }
            }
        }
    }
    
    public var outdatedAIToolCount: Int {
        aiTools.filter { $0.isOutdated }.count
    }
    
    public var outdatedNpmCount: Int {
        npmPackages.filter { $0.status.isOutdated }.count
    }
    
    public var outdatedPythonCount: Int {
        pythonPackages.filter { $0.status.isOutdated }.count
    }
    
    public var outdatedBrewCount: Int {
        brewPackages.filter { $0.status.isOutdated }.count
    }
    
    public var outdatedGitHubCount: Int {
        githubTools.filter { $0.isOutdated }.count
    }
    
    public var vulnerabilityCount: Int {
        vulnerabilities.count
    }
    
    public var groupedVulnerabilities: [PackageVulnerabilityGroup] {
        var groups: [String: [VulnerabilityItem]] = [:]
        for v in vulnerabilities {
            let key = "\(v.ecosystem.lowercased()):\(v.packageName.lowercased()):\(v.projectPath ?? "")"
            groups[key, default: []].append(v)
        }
        
        func severityScore(_ s: VulnerabilitySeverity) -> Int {
            switch s {
            case .critical: return 4
            case .high: return 3
            case .medium: return 2
            case .low: return 1
            case .unknown: return 0
            }
        }
        
        return groups.values.map { items in
            let first = items[0]
            return PackageVulnerabilityGroup(
                packageName: first.packageName,
                ecosystem: first.ecosystem,
                currentVersion: first.currentVersion,
                vulnerabilities: items
            )
        }.sorted { a, b in
            if a.highestSeverity != b.highestSeverity {
                return severityScore(a.highestSeverity) > severityScore(b.highestSeverity)
            }
            return a.packageName < b.packageName
        }
    }
    
    public var totalOutdatedCount: Int {
        outdatedAIToolCount + outdatedNpmCount + outdatedPythonCount + outdatedBrewCount + outdatedGitHubCount
    }
    
    public func loadSystemInfo() async {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        
        let nodeVer = (try? await ShellExecutor.shared.run(command: "node --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        let npmVer = (try? await ShellExecutor.shared.run(command: "npm --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        let pyVer = (try? await ShellExecutor.shared.run(command: "\(PythonRuntime.executable) --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        let brewVer = (try? await ShellExecutor.shared.run(command: "brew --version | head -n 1"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        
        self.systemInfo = SystemInfo(
            osVersion: os,
            nodeVersion: nodeVer,
            npmVersion: npmVer,
            pythonVersion: pyVer,
            brewVersion: brewVer
        )
    }
    
    public func scanAll() async {
        guard !isScanning else { return }
        isScanning = true
        appendLog("開始掃描系統安裝之所有套件、AI 工具與服務狀態...")
        
        async let aiTask = scanAITools()
        async let npmTask = scanNpm()
        async let pyTask = scanPython()
        async let brewTask = scanBrew()
        async let dbTask = scanDatabases()
        async let ghTask = scanGitHubTools()
        async let selfUpdateTask = checkSelfUpdate()
        
        _ = await (aiTask, npmTask, pyTask, brewTask, dbTask, ghTask, selfUpdateTask)
        
        self.lastScanDate = Date()
        self.isScanning = false
        appendLog("掃描完成。發現 \(totalOutdatedCount) 個待升級項目。")
        
        // Run security audit in background
        Task { await self.scanSecurityAudit() }
    }
    
    public func scanAITools() async {
        let defaultList = AIToolService.shared.defaultAITools()
        var updatedList: [AIToolItem] = []
        
        for var tool in defaultList {
            let local = await AIToolService.shared.detectLocalTool(item: tool)
            tool.isInstalled = local.isInstalled
            tool.currentVersion = local.version
            tool.binaryPath = local.binaryPath
            
            if let latest = await AIToolService.shared.fetchLatestVersion(for: tool.command) {
                tool.latestVersion = latest
            } else if local.isInstalled {
                tool.latestVersion = local.version
            }
            tool.lastChecked = Date()
            updatedList.append(tool)
        }
        
        self.aiTools = updatedList
    }
    
    public func upgradeAITool(item: AIToolItem, confirmedRemoteScript: Bool = false) async {
        guard !isActionRunning else { return }
        if item.updateRunsRemoteScript && !confirmedRemoteScript {
            appendLog("已取消 \(item.name) 升級：指令會執行遠端下載的腳本，需先確認。")
            return
        }
        isActionRunning = true
        currentActionPackageId = item.id
        
        appendLog("正在升級 AI 開發工具: \(item.name) (\(item.updateCommand))...")
        liveLogOutput = ""
        
        let stream = AIToolService.shared.upgradeTool(item: item)
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("\(item.name) 升級程序完成。")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let idx = self.aiTools.firstIndex(where: { $0.id == item.id }) {
                self.aiTools[idx].currentVersion = item.latestVersion ?? item.currentVersion
            }
            self.isActionRunning = false
            self.currentActionPackageId = nil
        }
    }
    
    public func installAITool(item: AIToolItem, confirmedRemoteScript: Bool = false) async {
        guard !isActionRunning else { return }
        if item.installRunsRemoteScript && !confirmedRemoteScript {
            appendLog("已取消 \(item.name) 安裝：指令會執行遠端下載的腳本，需先確認。")
            return
        }
        isActionRunning = true
        currentActionPackageId = item.id
        
        appendLog("正在安裝 AI 開發工具: \(item.name) (\(item.installCommand))...")
        liveLogOutput = ""
        
        let stream = AIToolService.shared.installTool(item: item)
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("\(item.name) 安裝程序完成。")
        self.isActionRunning = false
        self.currentActionPackageId = nil
        
        await scanAITools()
    }
    
    public func scanGitHubTools() async {
        guard !isCheckingGitHubReleases else { return }
        self.isCheckingGitHubReleases = true
        self.gitHubCheckSuccessMessage = nil
        appendLog("正在檢查 GitHub Releases 最新發布版本與本機應用程式狀態...")
        
        let tools = GitHubToolService.shared.loadTrackedTools()
        var updatedTools: [GitHubToolItem] = []
        
        // Concurrent inspection with task group for high responsiveness
        await withTaskGroup(of: GitHubToolItem.self) { group in
            for item in tools {
                group.addTask {
                    var mutable = item
                    let local = await GitHubToolService.shared.detectLocalTool(item: mutable)
                    mutable.isInstalled = local.isInstalled
                    mutable.currentVersion = local.version
                    if mutable.kind == .appBundle {
                        mutable.appPath = local.resolvedPath
                    } else {
                        mutable.binaryPath = local.resolvedPath
                    }
                    
                    let remote = await GitHubToolService.shared.checkRemoteRelease(owner: mutable.owner, repo: mutable.repo)
                    mutable.latestVersion = remote.latestVersion
                    mutable.htmlUrl = remote.releaseUrl
                    mutable.releaseNotes = remote.releaseNotes
                    mutable.assetDownloadUrl = remote.assetDownloadUrl
                    mutable.assetName = remote.assetName
                    mutable.lastChecked = Date()
                    return mutable
                }
            }
            
            for await item in group {
                updatedTools.append(item)
            }
        }
        
        // Preserve stable original order
        let sorted = tools.compactMap { orig in updatedTools.first(where: { $0.id == orig.id }) }
        self.githubTools = sorted.isEmpty ? updatedTools : sorted
        GitHubToolService.shared.saveTrackedTools(self.githubTools)
        
        let outdatedCount = self.githubTools.filter { $0.isOutdated }.count
        if outdatedCount > 0 {
            appendLog("✅ GitHub Releases 檢查完成：發現 \(outdatedCount) 個軟體有新版本可用！")
            self.gitHubCheckSuccessMessage = "發現 \(outdatedCount) 個可升級軟體"
        } else {
            appendLog("✅ GitHub Releases 檢查完成：所有已追蹤項目皆為最新版本。")
            self.gitHubCheckSuccessMessage = "所有項目皆為最新版本"
        }
        
        self.isCheckingGitHubReleases = false
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            if self?.gitHubCheckSuccessMessage != nil {
                self?.gitHubCheckSuccessMessage = nil
            }
        }
    }
    
    public func addTrackedGitHubTool(owner: String, repo: String, binaryName: String?) async {
        await addTrackedGitHubItem(owner: owner, repo: repo, binaryName: binaryName, kind: .cli, appPath: nil)
    }
    
    public func addTrackedGitHubItem(
        owner: String,
        repo: String,
        binaryName: String?,
        kind: GitHubToolKind = .cli,
        appPath: String? = nil
    ) async {
        guard InputValidator.isValidRepoComponent(owner), InputValidator.isValidRepoComponent(repo),
              binaryName.map({ $0.isEmpty || InputValidator.isValidPackageName($0) }) ?? true else {
            appendLog("已拒絕新增 GitHub 項目：owner、repo 或程式名稱含不允許的字元。")
            return
        }
        var tools = self.githubTools
        if let idx = tools.firstIndex(where: { $0.owner.lowercased() == owner.lowercased() && $0.repo.lowercased() == repo.lowercased() }) {
            tools[idx].appPath = appPath ?? tools[idx].appPath
            tools[idx].kind = kind
            self.githubTools = tools
            GitHubToolService.shared.saveTrackedTools(tools)
            return
        }
        
        var newTool = GitHubToolItem(owner: owner, repo: repo, binaryName: binaryName, kind: kind, appPath: appPath)
        let local = await GitHubToolService.shared.detectLocalTool(item: newTool)
        newTool.isInstalled = local.isInstalled
        newTool.currentVersion = local.version
        if kind == .appBundle {
            newTool.appPath = local.resolvedPath
        } else {
            newTool.binaryPath = local.resolvedPath
        }
        
        let remote = await GitHubToolService.shared.checkRemoteRelease(owner: owner, repo: repo)
        newTool.latestVersion = remote.latestVersion
        newTool.htmlUrl = remote.releaseUrl
        newTool.releaseNotes = remote.releaseNotes
        newTool.assetDownloadUrl = remote.assetDownloadUrl
        newTool.assetName = remote.assetName
        newTool.lastChecked = Date()
        
        tools.append(newTool)
        self.githubTools = tools
        GitHubToolService.shared.saveTrackedTools(tools)
        appendLog("已新增追蹤 GitHub 項目: \(owner)/\(repo) (\(kind.rawValue))")
    }
    
    @discardableResult
    public func autoDiscoverInstalledApps() async -> Int {
        let discovered = GitHubToolService.shared.scanDiscoverableMacApps()
        var addedCount = 0
        for item in discovered {
            if !self.githubTools.contains(where: { $0.owner.lowercased() == item.owner.lowercased() && $0.repo.lowercased() == item.repo.lowercased() }) {
                await addTrackedGitHubItem(
                    owner: item.owner,
                    repo: item.repo,
                    binaryName: item.binaryName,
                    kind: .appBundle,
                    appPath: item.appPath
                )
                addedCount += 1
            }
        }
        if addedCount > 0 {
            appendLog("自動偵測並加入 \(addedCount) 個本機安裝之開源 GitHub Mac 應用程式！")
        } else {
            appendLog("本機常見之開源 GitHub 應用程式已全數加入追蹤。")
        }
        return addedCount
    }
    
    public func removeTrackedGitHubTool(item: GitHubToolItem) {
        self.githubTools.removeAll(where: { $0.id == item.id })
        GitHubToolService.shared.saveTrackedTools(self.githubTools)
        appendLog("已取消追蹤: \(item.owner)/\(item.repo)")
    }
    
    public func scanSecurityAudit() async {
        guard !isAuditingSecurity else { return }
        self.isAuditingSecurity = true
        appendLog("正在啟動全面安全弱點稽核 (Google OSV CVE/GHSA 比對)...")
        
        var detectedVulns: [VulnerabilityItem] = []
        var seenIds = Set<String>()
        
        func record(_ vulns: [VulnerabilityItem]) {
            for v in vulns {
                let scope = v.environment?.pythonPath ?? v.projectPath ?? ""
                let key = "\(v.id)|\(v.packageName.lowercased())|\(scope)"
                if seenIds.insert(key).inserted { detectedVulns.append(v) }
            }
        }
        
        // 1. Audit system npm global packages
        record(await auditList(npmPackages.map { ($0.name, $0.currentVersion) }, ecosystem: "npm", environment: nil))
        
        // 2. Audit every Python environment: all interpreters (including the old system Python) and uv tool venvs
        for interpreter in pythonInterpreters where interpreter.hasPip {
            let env = PythonEnvironmentRef(
                kind: .interpreter, pythonPath: interpreter.path,
                label: "Python \(interpreter.version) (\(interpreter.source.rawValue))"
            )
            let packages = await PythonEnvironmentService.shared.installedPackages(pythonPath: interpreter.path)
            record(await auditList(packages, ecosystem: "PyPI", environment: env))
        }
        for env in await PythonEnvironmentService.shared.uvToolEnvironments() {
            let packages = await PythonEnvironmentService.shared.uvToolPackages(pythonPath: env.pythonPath)
            record(await auditList(packages, ecosystem: "PyPI", environment: env))
        }
        
        // 3. Audit local projects under the user-chosen projects folder (Settings), if any
        let projectsRoot = UserDefaults.standard.string(forKey: "projectsRootPath") ?? ""
        let userProjectsPath = URL(fileURLWithPath: projectsRoot)
        if !projectsRoot.isEmpty, FileManager.default.fileExists(atPath: userProjectsPath.path) {
            if let subfolders = try? FileManager.default.contentsOfDirectory(at: userProjectsPath, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) {
                for sub in subfolders {
                    let hasPkgJson = FileManager.default.fileExists(atPath: sub.appendingPathComponent("package.json").path)
                    let hasReqs = FileManager.default.fileExists(atPath: sub.appendingPathComponent("requirements.txt").path)
                    if hasPkgJson || hasReqs {
                        record(await SecurityService.shared.auditProjectDirectory(at: sub))
                    }
                }
            }
        }
        
        self.vulnerabilities = detectedVulns
        // Keep failure reasons only for groups that are still present after the rescan.
        let stillPresent = Set(groupedVulnerabilities.map { $0.id })
        func isCurrent(_ key: String) -> Bool { stillPresent.contains { key.hasPrefix($0 + "|") } }
        self.fixFailures = self.fixFailures.filter { isCurrent($0.key) }
        self.remediationPlans = self.remediationPlans.filter { isCurrent($0.key) }
        self.remediationNotes = self.remediationNotes.filter { isCurrent($0.key) }
        self.isAuditingSecurity = false
        if !detectedVulns.isEmpty {
            appendLog("⚠️ 全面安全稽核完成：偵測到 \(detectedVulns.count) 個已知安全性弱點 (CVE/GHSA)！")
        } else {
            appendLog("✅ 全面安全稽核完成：本機套件與開發專案均未發現已知 CVE 弱點。")
        }
    }
    
    /// Audits packages against OSV with a small amount of concurrency.
    private func auditList(_ packages: [(name: String, version: String)], ecosystem: String, environment: PythonEnvironmentRef?) async -> [VulnerabilityItem] {
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
    
    // MARK: - Alternative fixes (remove / move to an isolated environment)
    
    /// Newest Python 3.10+ interpreter, used for new uv tool environments.
    private func newestModernPython() -> PythonInterpreter? {
        pythonInterpreters.first { $0.hasPip && !$0.isEndOfLife }
    }
    
    /// Python for new uv tool environments: the newest installed 3.10+ interpreter, or a version uv can download.
    private func migrationTargetPython() -> String? {
        if let path = newestModernPython()?.path { return path }
        guard availableManagers.contains(.uv) else { return nil }
        return PythonLifecycle.recommendedMinor
    }
    
    /// Interpreters whose support has ended.
    public var endOfLifePythons: [PythonInterpreter] { pythonInterpreters.filter { $0.isEndOfLife } }
    
    /// True when the recommended Python minor version is not installed yet.
    public var needsRecommendedPython: Bool {
        !pythonInterpreters.contains { $0.minorVersion == PythonLifecycle.recommendedMinor }
    }
    
    /// Installs uv when needed, then the recommended Python. Returns false when it had to stop.
    @discardableResult
    public func upgradeToRecommendedPython(confirmedRemoteScript: Bool = false) async -> Bool {
        guard !isActionRunning else { return false }
        if !availableManagers.contains(.uv) {
            await installUV(confirmedRemoteScript: confirmedRemoteScript)
            guard availableManagers.contains(.uv) else {
                appendLog("一鍵升級中止：uv 尚未安裝成功。")
                return false
            }
        }
        guard needsRecommendedPython else { return true }
        await installPython(PythonRelease(source: .uv, version: PythonLifecycle.recommendedMinor))
        return pythonInterpreters.contains { $0.minorVersion == PythonLifecycle.recommendedMinor }
    }
    
    /// True when the terminal's `python3` runs an interpreter whose support has ended (or none at all).
    public var terminalPythonNeedsUpdate: Bool {
        guard let terminalPython else { return false }
        let parts = terminalPython.version.split(separator: ".")
        guard parts.count >= 2 else { return false }
        return PythonLifecycle.isEndOfLife(minor: "\(parts[0]).\(parts[1])")
    }
    
    /// Points the terminal's `python3` at the recommended uv-managed Python (installing it if needed).
    public func setTerminalPythonToRecommended() async {
        guard availableManagers.contains(.uv) else {
            appendLog("需要先安裝 uv，才能讓 python3 指向新版。")
            return
        }
        await runPythonAction(label: "讓 python3 指令使用 Python \(PythonLifecycle.recommendedMinor)") {
            PythonInterpreterService.shared.setTerminalDefaultStream(minor: PythonLifecycle.recommendedMinor)
        }
    }
    
    /// Installs uv. Without Homebrew this runs the official installer script, which needs confirmation.
    public func installUV(confirmedRemoteScript: Bool = false) async {
        let viaBrew = availableManagers.contains(.homebrew)
        if !viaBrew && !confirmedRemoteScript {
            appendLog("已取消安裝 uv：官方安裝腳本需要先確認。")
            return
        }
        await runPythonAction(label: "安裝 uv") {
            PythonInterpreterService.shared.installUVStream(viaHomebrew: viaBrew)
        }
    }
    
    /// Works out whether a vulnerable package can be removed, or its tool moved to an isolated environment.
    public func prepareRemediation(for group: PackageVulnerabilityGroup, environment env: PythonEnvironmentRef?) async {
        let key = group.key(for: env)
        remediationPlans[key] = nil
        remediationNotes[key] = nil
        guard let env, env.kind == .interpreter,
              let interpreter = pythonInterpreters.first(where: { $0.path == env.pythonPath }) else { return }
        switch await PythonEnvironmentService.shared.plan(
            packageName: group.packageName, interpreter: interpreter,
            targetPython: migrationTargetPython(), uvAvailable: availableManagers.contains(.uv)
        ) {
        case .plan(let plan): remediationPlans[key] = plan
        case .unavailable(let reason): remediationNotes[key] = reason
        }
    }
    
    /// Installs tools into uv tool environments (when needed), then removes the old copies.
    /// Nothing is removed unless every install succeeded.
    @discardableResult
    public func executeRemediation(_ plan: RemediationPlan, groupId: String, key: String, rescan: Bool = true) async -> Bool {
        guard !isActionRunning else { return false }
        guard pythonInterpreters.contains(where: { $0.path == plan.interpreterPath }) else {
            remediationNotes[key] = "找不到對應的 Python 環境，請重新掃描。"
            return false
        }
        let allNames = plan.toolsToInstall + plan.toolsAlreadyInUV + plan.packagesToRemove
        guard allNames.allSatisfy({ InputValidator.isValidPackageName($0) }) else {
            remediationNotes[key] = "套件名稱含不允許的字元，已拒絕。"
            return false
        }
        
        isActionRunning = true
        fixingVulnId = groupId
        pythonActionLabel = plan.kind == .migrate ? "搬到獨立環境" : "移除套件"
        liveLogOutput = ""
        defer {
            isActionRunning = false
            fixingVulnId = nil
            pythonActionLabel = nil
            actionProgress = 0
            actionStage = ""
        }
        
        if plan.kind == .migrate {
            guard let target = plan.targetPython,
                  target.hasPrefix("/") || target.range(of: #"^3\.\d+$"#, options: .regularExpression) != nil else {
                remediationNotes[key] = "沒有可用的新版 Python。"
                return false
            }
            let q = InputValidator.shellQuoted(target)
            for (i, tool) in plan.toolsToInstall.enumerated() {
                actionStage = "安裝 \(tool) 到獨立環境 (\(i + 1)/\(plan.toolsToInstall.count))..."
                appendLog("uv tool install \(tool)（Python：\(target)）")
                for await chunk in ShellExecutor.shared.stream(command: "uv tool install --python \(q) \(tool)") {
                    liveLogOutput += chunk
                }
                let installed = await PythonEnvironmentService.shared.uvToolEnvironments()
                let ok = ShellExecutor.shared.lastStreamStatus == 0
                    && installed.contains { PythonDependencyGraph.normalize($0.toolName ?? "") == PythonDependencyGraph.normalize(tool) }
                guard ok else {
                    appendLog("\(tool) 無法安裝到獨立環境，已中止，舊環境沒有任何變動。")
                    remediationNotes[key] = "\(tool) 無法安裝到獨立環境（可能與新版 Python 不相容），已中止，舊環境沒有任何變動。詳見執行日誌。"
                    return false
                }
            }
        }
        
        actionStage = "移除舊環境中的 \(plan.packagesToRemove.count) 個套件..."
        let py = InputValidator.shellQuoted(plan.interpreterPath)
        let names = plan.packagesToRemove.joined(separator: " ")
        appendLog("從 \(plan.interpreterLabel) 移除：\(names)")
        for await chunk in ShellExecutor.shared.stream(command: "\(py) -m pip uninstall -y \(names)") {
            liveLogOutput += chunk
        }
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            appendLog("移除舊套件失敗，請查看執行日誌。")
            remediationNotes[key] = "新環境已就緒，但從舊環境移除套件失敗。詳見執行日誌。"
            return false
        }
        
        appendLog("\(plan.packageName) 的修復完成（\(plan.kind == .migrate ? "已搬到獨立環境" : "已移除")）。")
        remediationPlans[key] = nil
        remediationNotes[key] = nil
        fixFailures[key] = nil
        isActionRunning = false
        if rescan {
            await scanPython()
            await scanSecurityAudit()
        }
        return true
    }
    
    // MARK: - One-click batch of alternative fixes
    
    public struct RemediationBatch: Identifiable {
        public struct Item: Identifiable {
            public var id: String { key }
            public let key: String
            public let plan: RemediationPlan
        }
        public let id = UUID()
        public let items: [Item]
    }
    
    /// Collects the alternative fixes for the given failed targets into one confirmation, merging duplicates.
    func proposeBatch(keys: [String]) {
        var seen = Set<String>()
        var items: [RemediationBatch.Item] = []
        for key in keys {
            guard let plan = remediationPlans[key] else { continue }
            let signature = "\(plan.kind)|\(plan.interpreterPath)|\(plan.toolsToInstall)|\(plan.packagesToRemove)"
            if seen.insert(signature).inserted { items.append(.init(key: key, plan: plan)) }
        }
        pendingBatch = items.isEmpty ? nil : RemediationBatch(items: items)
    }
    
    /// Runs every confirmed plan, skipping plans whose packages an earlier plan already removed.
    public func runBatch(_ batch: RemediationBatch) async {
        pendingBatch = nil
        guard !isActionRunning else { return }
        var removed = Set<String>()
        var succeeded = 0
        var failed = 0
        for (index, item) in batch.items.enumerated() {
            let names = Set(item.plan.packagesToRemove.map { PythonDependencyGraph.normalize($0) })
            if names.isSubset(of: removed) { continue }
            appendLog("批次修復 \(index + 1)/\(batch.items.count)：\(item.plan.packageName)")
            if await executeRemediation(item.plan, groupId: item.key, key: item.key, rescan: false) {
                removed.formUnion(names)
                succeeded += 1
            } else {
                failed += 1
            }
        }
        appendLog("替代修復結束：成功 \(succeeded) 項，失敗 \(failed) 項。重新掃描中...")
        await scanPython()
        await scanSecurityAudit()
    }
    
    public func auditLocalProject(at url: URL) async {
        guard !isAuditingSecurity else { return }
        isAuditingSecurity = true
        appendLog("正在透過 Google OSV 審查本機網頁專案前後端相依套件安全漏洞: \(url.lastPathComponent)...")
        
        let projectVulns = await SecurityService.shared.auditProjectDirectory(at: url)
        if !projectVulns.isEmpty {
            for v in projectVulns {
                if !self.vulnerabilities.contains(where: { $0.id == v.id }) {
                    self.vulnerabilities.append(v)
                }
            }
            appendLog("專案安全稽核完成：在 \(url.lastPathComponent) 偵測到 \(projectVulns.count) 個安全性漏洞！")
        } else {
            appendLog("專案安全稽核完成：\(url.lastPathComponent) 未偵測到已知安全性弱點。")
        }
        self.isAuditingSecurity = false
    }
    
    private enum FixOutcome {
        case fixed
        case failed(String)
    }
    
    /// Runs a fix command, then checks the installed version instead of trusting the exit status.
    private func executeFix(command: String, packageName: String, ecosystem: String, targetVersion: String?, environment: PythonEnvironmentRef? = nil) async -> FixOutcome {
        let eco = ecosystem.lowercased()
        let interpreter = environment.flatMap { env in pythonInterpreters.first { $0.path == env.pythonPath } }
        if environment?.kind != .uvTool, eco.contains("pypi") || eco.contains("pip") || eco.contains("python") {
            let target = interpreter ?? PythonRuntime.current
            if let target, target.isExternallyManaged {
                return .failed("Python \(target.version)（\(target.source.rawValue)）受 PEP 668 保護，不允許用 pip 直接修改。")
            }
        }
        var output = ""
        for await chunk in ShellExecutor.shared.stream(command: command) {
            self.liveLogOutput += chunk
            output += chunk
        }
        var lastStatus = ShellExecutor.shared.lastStreamStatus
        
        // The fixed version may not support this Python; try the newest compatible release as best effort.
        let isPip = ecosystem.lowercased().contains("pypi") || ecosystem.lowercased().contains("pip")
        if lastStatus != 0, isPip, command.contains(">="),
           output.contains("No matching distribution") || output.contains("Could not find a version"),
           let safeName = InputValidator.safeName(packageName) {
            let python = environment.map { InputValidator.shellQuoted($0.pythonPath) } ?? PythonRuntime.executable
            let fallback = "\(python) -m pip install --upgrade \(safeName)"
            appendLog("指定的安全版本無法安裝，改裝目前 Python 可用的最新版本：\(fallback)")
            for await chunk in ShellExecutor.shared.stream(command: fallback) {
                self.liveLogOutput += chunk
                output += chunk
            }
            lastStatus = ShellExecutor.shared.lastStreamStatus
        }
        
        let installed = await installedVersion(packageName: packageName, ecosystem: ecosystem, environment: environment)
        
        if let target = targetVersion, !target.isEmpty {
            if let installed {
                if installed.compare(target, options: .numeric) != .orderedAscending {
                    return .fixed
                }
                if output.contains("Requires-Python") || output.contains("No matching distribution") {
                    let py = interpreter.map { "Python \($0.version)" } ?? (systemInfo.pythonVersion.isEmpty ? "Python" : systemInfo.pythonVersion)
                    return .failed("無法修復：安全版本 \(target) 不支援目前使用的 \(py)，現有版本 \(installed) 已是此環境能安裝的最新版。請改用較新的 Python 或自行升級。")
                }
                return .failed("升級後版本為 \(installed)，仍低於安全版本 \(target)。")
            }
        }
        return lastStatus == 0 ? .fixed : .failed("修復指令執行失敗，請查看執行日誌。")
    }
    
    private func installedVersion(packageName: String, ecosystem: String, environment: PythonEnvironmentRef? = nil) async -> String? {
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
    
    /// Fixes one package in every environment it is installed in.
    /// Returns true only when every environment actually reached the safe version.
    @discardableResult
    public func fixVulnerabilityGroup(group: PackageVulnerabilityGroup) async -> Bool {
        guard !isActionRunning else { return false }
        let targets = group.fixTargets
        guard targets.contains(where: { !$0.command.isEmpty }) else {
            appendLog("\(group.packageName) 無法自動修復，請手動處理。")
            for t in targets { fixFailures[group.key(for: t.environment)] = "此套件無法自動修復，請手動處理。" }
            return false
        }
        self.isActionRunning = true
        self.fixingVulnId = group.id
        self.actionProgress = 0.1
        liveLogOutput = ""
        
        var failedEnvironments: [PythonEnvironmentRef?] = []
        for (index, target) in targets.enumerated() {
            let key = group.key(for: target.environment)
            fixFailures[key] = nil
            remediationPlans[key] = nil
            remediationNotes[key] = nil
            let place = target.environment?.label ?? "全域"
            guard !target.command.isEmpty else {
                fixFailures[key] = "這個環境無法自動修復，請手動處理。"
                failedEnvironments.append(target.environment)
                continue
            }
            self.actionStage = "正在修復 \(group.packageName)（\(place)）\(index + 1)/\(targets.count)..."
            self.actionProgress = 0.1 + 0.8 * Double(index) / Double(targets.count)
            appendLog("正在修復 \(group.packageName)（\(place)），執行：\(target.command)")
            
            let outcome = await executeFix(
                command: target.command,
                packageName: group.packageName,
                ecosystem: group.ecosystem,
                targetVersion: group.targetSafeVersion,
                environment: target.environment
            )
            switch outcome {
            case .fixed:
                appendLog("套件 \(group.packageName)（\(place)）修復完成。")
                withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                    self.vulnerabilities.removeAll {
                        $0.packageName.lowercased() == group.packageName.lowercased()
                            && $0.projectPath == group.projectPath
                            && $0.environment == target.environment
                    }
                }
            case .failed(let reason):
                appendLog("套件 \(group.packageName)（\(place)）修復失敗：\(reason)")
                fixFailures[key] = reason
                failedEnvironments.append(target.environment)
            }
        }
        
        if failedEnvironments.isEmpty {
            self.actionProgress = 1.0
            self.actionStage = "修復完成！"
            self.completedPackageId = group.id
            try? await Task.sleep(nanoseconds: 650_000_000)
        }
        self.isActionRunning = false
        self.fixingVulnId = nil
        self.completedPackageId = nil
        self.actionProgress = 0.0
        self.actionStage = ""
        
        for env in failedEnvironments {
            await prepareRemediation(for: group, environment: env)
        }
        proposeBatch(keys: failedEnvironments.map { group.key(for: $0) })
        return failedEnvironments.isEmpty
    }
    
    public func fixVulnerability(item: VulnerabilityItem) async {
        guard !isActionRunning else { return }
        guard !item.fixCommand.isEmpty else {
            appendLog("\(item.packageName) 無法自動修復，請手動處理。")
            return
        }
        self.isActionRunning = true
        self.fixingVulnId = item.id
        self.fixFailures[item.id] = nil
        self.actionStage = "正在修復 \(item.packageName)..."
        self.actionProgress = 0.2
        appendLog("正在修復弱點 \(item.packageName) (\(item.cveId))，執行指令：\(item.fixCommand)")
        liveLogOutput = ""
        
        self.actionProgress = 0.5
        let outcome = await executeFix(
            command: item.fixCommand,
            packageName: item.packageName,
            ecosystem: item.ecosystem,
            targetVersion: item.fixedVersion,
            environment: item.environment
        )
        
        if case .failed(let reason) = outcome {
            appendLog("弱點 \(item.packageName) 修復失敗：\(reason)")
            self.fixFailures[item.id] = reason
            self.isActionRunning = false
            self.fixingVulnId = nil
            self.actionProgress = 0.0
            self.actionStage = ""
            return
        }
        
        self.actionProgress = 1.0
        self.actionStage = "修復完成！"
        self.completedPackageId = item.id
        appendLog("弱點 \(item.packageName) 修復完成。")
        
        try? await Task.sleep(nanoseconds: 800_000_000)
        self.isActionRunning = false
        self.fixingVulnId = nil
        self.completedPackageId = nil
        
        withAnimation {
            self.vulnerabilities.removeAll { $0.id == item.id }
        }
    }
    
    public func fixAllVulnerabilities() async {
        guard !isActionRunning, !vulnerabilities.isEmpty else { return }
        self.isActionRunning = true
        self.isFixingAllVulnerabilities = true
        self.actionStage = "準備批次修復已知弱點..."
        self.actionProgress = 0.05
        appendLog("啟動批次修復所有可升級之安全弱點...")
        
        let groups = groupedVulnerabilities
        let jobs = groups.flatMap { group in group.fixTargets.map { (group, $0) } }
        var fixedCount = 0
        var failedCount = 0
        var failedJobs: [(PackageVulnerabilityGroup, PythonEnvironmentRef?)] = []
        for (index, job) in jobs.enumerated() {
            let (group, target) = job
            let place = target.environment?.label ?? "全域"
            self.actionStage = "正在修復 (\(index + 1)/\(jobs.count)) \(group.packageName)（\(place)）..."
            self.actionProgress = Double(index) / Double(max(jobs.count, 1))
            let key = group.key(for: target.environment)
            guard !target.command.isEmpty else {
                appendLog("略過 \(group.packageName)（\(place)）：無法自動修復。")
                continue
            }
            appendLog("修復套件 \(group.packageName)（\(place)）：\(target.command)")
            
            let outcome = await executeFix(
                command: target.command,
                packageName: group.packageName,
                ecosystem: group.ecosystem,
                targetVersion: group.targetSafeVersion,
                environment: target.environment
            )
            switch outcome {
            case .fixed:
                fixFailures[key] = nil
                fixedCount += 1
            case .failed(let reason):
                fixFailures[key] = reason
                failedCount += 1
                failedJobs.append((group, target.environment))
                appendLog("套件 \(group.packageName)（\(place)）修復失敗：\(reason)")
            }
        }
        
        appendLog("批次修復結束：成功 \(fixedCount) 項，失敗 \(failedCount) 項。")
        self.actionProgress = 1.0
        self.actionStage = "批次修復結束，正在分析替代做法..."
        self.isFixingAllVulnerabilities = false
        self.isActionRunning = false
        
        for (group, env) in failedJobs { await prepareRemediation(for: group, environment: env) }
        let failedKeys = failedJobs.map { $0.0.key(for: $0.1) }
        await scanSecurityAudit()
        proposeBatch(keys: failedKeys)
    }
    
    public func checkSelfUpdate() async {
        let (hasUpdate, latest, notes, url) = await GitHubReleaseService.shared.checkDevKeeperSelfUpdate(currentAppVersion: AppViewModel.appVersion)
        self.appUpdateAvailable = hasUpdate
        self.latestAppVersion = latest
        self.appReleaseNotes = notes
        self.appDownloadUrl = url
        if hasUpdate {
            appendLog("發現 DevKeeper 新版本: v\(latest)！可至 GitHub 查看更新。")
        }
    }
    
    public func scanNpm() async {
        do {
            let items = try await NpmService.shared.fetchInstalledPackages()
            self.npmPackages = items
            
            await withTaskGroup(of: (String, String?, String?, String?).self) { group in
                for item in items {
                    group.addTask {
                        let info = await NpmService.shared.checkLatestVersion(for: item.name)
                        return (item.name, info.latestVersion, info.description, info.homepage)
                    }
                }
                
                for await (name, latest, desc, home) in group {
                    if let index = self.npmPackages.firstIndex(where: { $0.name == name }) {
                        self.npmPackages[index].latestVersion = latest
                        self.npmPackages[index].description = desc
                        self.npmPackages[index].homepage = home
                        self.npmPackages[index].status = PackageItem.computeUpdateStatus(
                            current: self.npmPackages[index].currentVersion,
                            latest: latest
                        )
                    }
                }
            }
        } catch {
            appendLog("npm 掃描失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Python interpreters
    
    /// Detects interpreters and applies the saved selection (only paths that were actually discovered).
    public func scanPythonInterpreters() async {
        guard !isScanningPython else { return }
        isScanningPython = true
        defer { isScanningPython = false }
        
        let found = await PythonInterpreterService.shared.discover()
        self.pythonInterpreters = found
        applySelectedPython()
        
        self.availableManagers = await PythonInterpreterService.shared.availableManagers()
        self.terminalPython = await PythonInterpreterService.shared.terminalPython()
        self.uvLatestPatches = await PythonInterpreterService.shared.uvLatestPatches()
        self.installablePythons = await PythonInterpreterService.shared.installableReleases(installed: found)
    }
    
    private func applySelectedPython() {
        let saved = UserDefaults.standard.string(forKey: PythonRuntime.selectedPathKey) ?? ""
        PythonRuntime.setCurrent(pythonInterpreters.first { $0.path == saved } ?? automaticPython())
    }
    
    /// Picks a modern interpreter that pip may write to; the old system Python is used only as a last resort.
    private func automaticPython() -> PythonInterpreter? {
        let usable = pythonInterpreters.filter { $0.hasPip }
        let supported = usable.filter { !$0.isEndOfLife }
        // pythonInterpreters is sorted newest first.
        return supported.first { !$0.isExternallyManaged } ?? supported.first ?? usable.first
    }
    
    /// True when the user has not chosen an interpreter and DevKeeper picked one automatically.
    public var isPythonAutoSelected: Bool {
        let saved = UserDefaults.standard.string(forKey: PythonRuntime.selectedPathKey) ?? ""
        return !pythonInterpreters.contains { $0.path == saved }
    }
    
    public var selectedPythonPath: String? { PythonRuntime.current?.path }
    
    /// Switches the interpreter used for pip scans and fixes, then rescans.
    public func selectPython(_ interpreter: PythonInterpreter?) async {
        guard interpreter == nil || pythonInterpreters.contains(interpreter!) else { return }
        UserDefaults.standard.set(interpreter?.path ?? "", forKey: PythonRuntime.selectedPathKey)
        applySelectedPython()
        appendLog("DevKeeper 改用 Python：\(interpreter.map { "\($0.version) (\($0.source.rawValue))" } ?? "自動選擇")")
        await loadSystemInfo()
        await scanPython()
        await scanSecurityAudit()
    }
    
    /// Latest patch version available for an interpreter, when its manager can tell.
    public func upgradeTarget(for interpreter: PythonInterpreter) -> String? {
        switch interpreter.source {
        case .uv:
            if let latest = uvLatestPatches[interpreter.minorVersion],
               latest.compare(interpreter.version, options: .numeric) == .orderedDescending {
                return latest
            }
            return nil
        case .homebrew:
            let name = "python@\(interpreter.minorVersion)"
            return brewPackages.first { $0.name == name && $0.status.isOutdated }?.latestVersion
        case .pyenv, .system:
            return nil
        }
    }
    
    public func upgradePython(_ interpreter: PythonInterpreter) async {
        await runPythonAction(label: "升級 Python \(interpreter.version) (\(interpreter.source.rawValue))") {
            PythonInterpreterService.shared.upgradeStream(interpreter)
        }
    }
    
    public func installPython(_ release: PythonRelease) async {
        await runPythonAction(label: "安裝 Python \(release.version) (\(release.source.rawValue))") {
            PythonInterpreterService.shared.installStream(release)
        }
    }
    
    private func runPythonAction(label: String, stream: () -> AsyncStream<String>) async {
        guard !isActionRunning else { return }
        isActionRunning = true
        pythonActionLabel = label
        liveLogOutput = ""
        appendLog("開始\(label)...")
        
        for await chunk in stream() {
            liveLogOutput += chunk
        }
        let ok = ShellExecutor.shared.lastStreamStatus == 0
        appendLog(ok ? "\(label)完成。" : "\(label)失敗，請查看執行日誌。")
        
        pythonActionLabel = nil
        isActionRunning = false
        await scanPythonInterpreters()
        if ok { await scanBrew() }
    }
    
    public func scanPython() async {
        do {
            var items = try await PythonService.shared.fetchInstalledPackages()
            let outdatedMap = await PythonService.shared.fetchOutdatedMap()
            
            // First pass: compute exact update status based on local Python runtime compatibility
            for i in 0..<items.count {
                let key = items[i].name.lowercased()
                if let compatibleLatest = outdatedMap[key] {
                    items[i].latestVersion = compatibleLatest
                    items[i].status = PackageItem.computeUpdateStatus(
                        current: items[i].currentVersion,
                        latest: compatibleLatest
                    )
                } else {
                    items[i].latestVersion = items[i].currentVersion
                    items[i].status = .upToDate
                }
            }
            
            self.pythonPackages = items
            
            // Second pass: fetch package description and homepage for genuinely outdated items
            let outdatedItems = items.filter { $0.status.isOutdated }
            await withTaskGroup(of: (String, String?, String?).self) { group in
                for item in outdatedItems.prefix(30) {
                    group.addTask {
                        let info = await PythonService.shared.checkLatestVersion(for: item.name)
                        return (item.name, info.description, info.homepage)
                    }
                }
                
                for await (name, desc, home) in group {
                    if let index = self.pythonPackages.firstIndex(where: { $0.name == name }) {
                        self.pythonPackages[index].description = desc
                        self.pythonPackages[index].homepage = home
                    }
                }
            }
        } catch {
            appendLog("Python 套件掃描失敗: \(error.localizedDescription)")
        }
    }
    
    public func scanBrew() async {
        do {
            let items = try await BrewService.shared.fetchPackages()
            self.brewPackages = items
        } catch {
            appendLog("Homebrew 掃描失敗: \(error.localizedDescription)")
        }
    }
    
    public func scanDatabases() async {
        do {
            let services = try await DatabaseService.shared.fetchServices()
            self.databaseServices = services
        } catch {
            appendLog("資料庫服務掃描失敗: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Actions (Upgrade, Clean Uninstall, Install)
    
    public func upgradeSingle(package: PackageItem) async {
        guard !isActionRunning else { return }
        isActionRunning = true
        currentActionPackageId = package.id
        completedPackageId = nil
        actionProgress = 0.15
        actionStage = "準備更新環境..."
        
        appendLog("正在升級: \(package.name)...")
        liveLogOutput = ""
        
        let stream: AsyncStream<String>
        switch package.type {
        case .npm:
            stream = NpmService.shared.upgradePackage(name: package.name)
        case .python:
            stream = PythonService.shared.upgradePackage(name: package.name)
        case .brewFormula:
            stream = BrewService.shared.upgradePackage(name: package.name, isCask: false)
        case .brewCask:
            stream = BrewService.shared.upgradePackage(name: package.name, isCask: true)
        case .database:
            stream = DatabaseService.shared.installDatabase(name: package.name)
        }
        
        for await chunk in stream {
            self.liveLogOutput += chunk
            let lower = chunk.lowercased()
            if lower.contains("download") || lower.contains("fetch") || lower.contains("get ") {
                self.actionProgress = min(max(self.actionProgress, 0.35) + 0.08, 0.6)
                self.actionStage = "正在下載最新套件..."
            } else if lower.contains("install") || lower.contains("unpack") || lower.contains("building") || lower.contains("pouring") {
                self.actionProgress = min(max(self.actionProgress, 0.65) + 0.08, 0.88)
                self.actionStage = "正在解壓與編譯安裝..."
            } else if lower.contains("success") || lower.contains("installed") || lower.contains("cleanup") {
                self.actionProgress = 0.95
                self.actionStage = "完成配置中..."
            }
        }
        
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            appendLog("\(package.name) 升級失敗，請查看日誌。")
            self.isActionRunning = false
            self.currentActionPackageId = nil
            self.actionProgress = 0.0
            self.actionStage = ""
            return
        }
        
        // Mark 100% completed
        self.actionProgress = 1.0
        self.actionStage = "升級完成！"
        self.completedPackageId = package.id
        appendLog("\(package.name) 升級程序完成。")
        
        // Wait 0.7s so user clearly sees the 100% completed status
        try? await Task.sleep(nanoseconds: 700_000_000)
        
        // Smoothly update local state in-memory so the package immediately vanishes from Outdated list with native spring animation
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            self.applyPackageUpgradedLocally(package)
            self.isActionRunning = false
            self.currentActionPackageId = nil
            self.completedPackageId = nil
            self.actionProgress = 0.0
            self.actionStage = ""
        }
    }
    
    private func applyPackageUpgradedLocally(_ package: PackageItem) {
        let newVersion = package.latestVersion ?? package.currentVersion
        switch package.type {
        case .python:
            if let idx = self.pythonPackages.firstIndex(where: { $0.id == package.id || $0.name == package.name }) {
                self.pythonPackages[idx].currentVersion = newVersion
                self.pythonPackages[idx].status = .upToDate
            }
        case .brewFormula, .brewCask:
            if let idx = self.brewPackages.firstIndex(where: { $0.id == package.id || $0.name == package.name }) {
                self.brewPackages[idx].currentVersion = newVersion
                self.brewPackages[idx].status = .upToDate
            }
        case .npm:
            if let idx = self.npmPackages.firstIndex(where: { $0.id == package.id || $0.name == package.name }) {
                self.npmPackages[idx].currentVersion = newVersion
                self.npmPackages[idx].status = .upToDate
            }
        case .database:
            break
        }
    }
    
    public func cleanUninstall(package: PackageItem) async {
        guard !isActionRunning else { return }
        isActionRunning = true
        currentActionPackageId = package.id
        
        appendLog("正在執行乾淨移除: \(package.name)...")
        liveLogOutput = ""
        
        let stream: AsyncStream<String>
        switch package.type {
        case .npm:
            stream = NpmService.shared.cleanUninstallPackage(name: package.name)
        case .python:
            stream = PythonService.shared.cleanUninstallPackage(name: package.name)
        case .brewFormula:
            stream = BrewService.shared.cleanUninstallPackage(name: package.name, isCask: false)
        case .brewCask:
            stream = BrewService.shared.cleanUninstallPackage(name: package.name, isCask: true)
        case .database:
            stream = DatabaseService.shared.cleanUninstallDatabase(name: package.name)
        }
        
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            appendLog("\(package.name) 移除失敗，請查看日誌。")
            self.isActionRunning = false
            self.currentActionPackageId = nil
            return
        }
        
        appendLog("\(package.name) 已完成乾淨移除。")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            switch package.type {
            case .python:
                self.pythonPackages.removeAll { $0.id == package.id || $0.name == package.name }
            case .brewFormula, .brewCask:
                self.brewPackages.removeAll { $0.id == package.id || $0.name == package.name }
            case .npm:
                self.npmPackages.removeAll { $0.id == package.id || $0.name == package.name }
            case .database:
                break
            }
            self.isActionRunning = false
            self.currentActionPackageId = nil
        }
    }
    
    public func installNewPackage(name: String, type: PackageType) async {
        guard !isActionRunning, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isActionRunning = true
        let cleanName = name.trimmingCharacters(in: .whitespaces)
        
        appendLog("正在安裝 \(type.displayName): \(cleanName)...")
        liveLogOutput = ""
        
        let stream: AsyncStream<String>
        switch type {
        case .npm:
            stream = NpmService.shared.installPackage(name: cleanName)
        case .python:
            stream = PythonService.shared.installPackage(name: cleanName)
        case .brewFormula:
            stream = BrewService.shared.installPackage(name: cleanName, isCask: false)
        case .brewCask:
            stream = BrewService.shared.installPackage(name: cleanName, isCask: true)
        case .database:
            stream = DatabaseService.shared.installDatabase(name: cleanName)
        }
        
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        if ShellExecutor.shared.lastStreamStatus == 0 {
            appendLog("\(cleanName) 安裝程序完成。")
        } else {
            appendLog("\(cleanName) 安裝失敗，請查看日誌。")
        }
        self.isActionRunning = false
        
        await refreshPackageType(type)
    }
    
    // MARK: - Database Service Controls
    
    public func controlDatabaseService(name: String, action: String) async {
        guard !isActionRunning else { return }
        isActionRunning = true
        appendLog("正在對資料庫服務 \(name) 執行 \(action)...")
        liveLogOutput = ""
        
        let stream: AsyncStream<String>
        switch action {
        case "start":
            stream = DatabaseService.shared.startService(name: name)
        case "stop":
            stream = DatabaseService.shared.stopService(name: name)
        case "restart":
            stream = DatabaseService.shared.restartService(name: name)
        default:
            stream = DatabaseService.shared.startService(name: name)
        }
        
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("資料庫服務 \(name) 操作完成。")
        self.isActionRunning = false
        await scanDatabases()
    }
    
    // MARK: - Batch Upgrades
    
    public func upgradeAllOutdatedNpm() async {
        guard !isActionRunning else { return }
        let outdated = npmPackages.filter { $0.status.isOutdated }
        guard !outdated.isEmpty else { return }
        
        isActionRunning = true
        appendLog("正在批次升級全域 npm 套件...")
        liveLogOutput = ""
        
        let stream = NpmService.shared.upgradeAll(packages: outdated.map { $0.name })
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("全域 npm 批次升級完成。")
        self.isActionRunning = false
        await scanNpm()
    }
    
    public func upgradeAllOutdatedBrew() async {
        guard !isActionRunning else { return }
        isActionRunning = true
        appendLog("正在執行 brew upgrade...")
        liveLogOutput = ""
        
        let stream = BrewService.shared.upgradeAll()
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("Homebrew 升級完成。")
        self.isActionRunning = false
        await scanBrew()
    }
    
    private func refreshPackageType(_ type: PackageType) async {
        switch type {
        case .npm: await scanNpm()
        case .python: await scanPython()
        case .brewFormula, .brewCask: await scanBrew()
        case .database:
            await scanDatabases()
            await scanBrew()
        }
    }
    
    public func appendLog(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let formatted = "[\(timestamp)] \(message)"
        self.consoleLogs.append(formatted)
    }
}

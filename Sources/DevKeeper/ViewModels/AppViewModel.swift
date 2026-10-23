import Foundation
import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "總覽"
    case aiTools = "AI 開發工具"
    case npm = "npm 套件"
    case python = "Python 套件"
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
        let pyVer = (try? await ShellExecutor.shared.run(command: "python3 --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
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
    
    public func upgradeAITool(item: AIToolItem) async {
        guard !isActionRunning else { return }
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
    
    public func installAITool(item: AIToolItem) async {
        guard !isActionRunning else { return }
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
    
    public func autoDiscoverInstalledApps() async {
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
        
        // 1. Audit system npm global packages
        for pkg in npmPackages.prefix(30) {
            let vulns = await SecurityService.shared.auditPackage(name: pkg.name, version: pkg.currentVersion, ecosystem: "npm")
            for v in vulns where !seenIds.contains(v.id) {
                seenIds.insert(v.id)
                detectedVulns.append(v)
            }
        }
        
        // 2. Audit system Python packages
        for pkg in pythonPackages.prefix(30) {
            let vulns = await SecurityService.shared.auditPackage(name: pkg.name, version: pkg.currentVersion, ecosystem: "PyPI")
            for v in vulns where !seenIds.contains(v.id) {
                seenIds.insert(v.id)
                detectedVulns.append(v)
            }
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
                        let projVulns = await SecurityService.shared.auditProjectDirectory(at: sub)
                        for v in projVulns where !seenIds.contains(v.id) {
                            seenIds.insert(v.id)
                            detectedVulns.append(v)
                        }
                    }
                }
            }
        }
        
        self.vulnerabilities = detectedVulns
        self.isAuditingSecurity = false
        if !detectedVulns.isEmpty {
            appendLog("⚠️ 全面安全稽核完成：偵測到 \(detectedVulns.count) 個已知安全性弱點 (CVE/GHSA)！")
        } else {
            appendLog("✅ 全面安全稽核完成：本機套件與開發專案均未發現已知 CVE 弱點。")
        }
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
    
    public func fixVulnerabilityGroup(group: PackageVulnerabilityGroup) async {
        guard !isActionRunning else { return }
        guard !group.fixCommand.isEmpty else {
            appendLog("\(group.packageName) 無法自動修復，請手動處理。")
            return
        }
        self.isActionRunning = true
        self.fixingVulnId = group.id
        self.actionStage = "正在修復套件 \(group.packageName)..."
        self.actionProgress = 0.2
        appendLog("正在修復 \(group.packageName)（涵蓋 \(group.cveList.count) 個弱點），執行：\(group.fixCommand)")
        
        self.actionProgress = 0.5
        var output = ""
        let stream = ShellExecutor.shared.stream(command: group.fixCommand)
        for await chunk in stream {
            self.liveLogOutput += chunk
            output += chunk
        }
        
        // If the strict version constraint failed (e.g. Requires-Python on current macOS), fallback to generic upgrade
        if (output.contains("No matching distribution") || output.contains("Could not find a version")) && group.fixCommand.contains(">=") {
            let fallbackCommand = "python3 -m pip install --upgrade \(InputValidator.safeName(group.packageName) ?? "")"
            appendLog("⚠️ 指定修復版本可能不相容當前 Python，改採相容最佳升級：\(fallbackCommand)")
            let fallbackStream = ShellExecutor.shared.stream(command: fallbackCommand)
            for await chunk in fallbackStream {
                self.liveLogOutput += chunk
            }
        }
        
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            appendLog("套件 \(group.packageName) 修復失敗，請查看日誌。")
            self.isActionRunning = false
            self.fixingVulnId = nil
            self.actionProgress = 0.0
            self.actionStage = ""
            return
        }
        
        self.actionProgress = 1.0
        self.actionStage = "修復完成！"
        self.completedPackageId = group.id
        appendLog("套件 \(group.packageName) 修復完成。")
        
        // Wait 0.65s so user sees the celebration status
        try? await Task.sleep(nanoseconds: 650_000_000)
        
        // Immediately and smoothly remove from memory so the card smoothly vanishes with native spring animation!
        withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
            self.vulnerabilities.removeAll {
                $0.packageName.lowercased() == group.packageName.lowercased() && $0.projectPath == group.projectPath
            }
            self.isActionRunning = false
            self.fixingVulnId = nil
            self.completedPackageId = nil
            self.actionProgress = 0.0
            self.actionStage = ""
        }
    }
    
    public func fixVulnerability(item: VulnerabilityItem) async {
        guard !isActionRunning else { return }
        guard !item.fixCommand.isEmpty else {
            appendLog("\(item.packageName) 無法自動修復，請手動處理。")
            return
        }
        self.isActionRunning = true
        self.fixingVulnId = item.id
        self.actionStage = "正在修復 \(item.packageName)..."
        self.actionProgress = 0.2
        appendLog("正在修復弱點 \(item.packageName) (\(item.cveId))，執行指令：\(item.fixCommand)")
        
        self.actionProgress = 0.5
        let stream = ShellExecutor.shared.stream(command: item.fixCommand)
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        guard ShellExecutor.shared.lastStreamStatus == 0 else {
            appendLog("弱點 \(item.packageName) 修復失敗，請查看日誌。")
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
        
        let uniquePackages = Array(Set(vulnerabilities.map { $0.packageName }))
        for (index, pkg) in uniquePackages.enumerated() {
            guard let vuln = vulnerabilities.first(where: { $0.packageName == pkg }) else { continue }
            self.actionStage = "正在修復 (\(index + 1)/\(uniquePackages.count)) \(pkg)..."
            self.actionProgress = Double(index) / Double(max(uniquePackages.count, 1))
            guard !vuln.fixCommand.isEmpty else {
                appendLog("略過 \(pkg)：無法自動修復。")
                continue
            }
            appendLog("修復套件 \(pkg)：\(vuln.fixCommand)")
            
            for await chunk in ShellExecutor.shared.stream(command: vuln.fixCommand) {
                self.liveLogOutput += chunk
            }
            if ShellExecutor.shared.lastStreamStatus != 0 {
                appendLog("套件 \(pkg) 修復失敗。")
            }
        }
        
        self.actionProgress = 1.0
        self.actionStage = "批次修復完成！正在重新稽核..."
        self.isFixingAllVulnerabilities = false
        self.isActionRunning = false
        
        await scanSecurityAudit()
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

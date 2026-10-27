import DevKeeperCore
import Foundation
import SwiftUI

public enum NavigationTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "總覽"
    case aiTools = "AI 開發工具"
    case npm = "npm 套件"
    case python = "Python 套件"
    case brew = "Homebrew"
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
    /// Where the app found `node` and `npm`; shows which install (Homebrew, nvm, ...) the versions belong to.
    public var nodePath: String = ""
    public var npmPath: String = ""
}

public enum UVScanState: Equatable, Sendable {
    case unknown, notInstalled, failed, ready
    /// The outdated lookup failed, so tools are listed without update status.
    case readyWithoutUpdateStatus
}

/// Whether the vulnerability list can be trusted as "nothing found".
public enum AuditState: Equatable, Sendable {
    /// No audit has finished since launch (or results were cleared).
    case notRun
    /// Every lookup got an answer.
    case complete
    /// Some lookups failed, so a short or empty list may be missing entries.
    case incomplete(failed: Int)
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public var selectedTab: NavigationTab = .overview
    @Published public var aiTools: [AIToolItem] = []
    @Published public var npmPackages: [PackageItem] = []
    @Published public var pythonPackages: [PackageItem] = []
    @Published public var brewPackages: [PackageItem] = []
    @Published public var databaseServices: [DatabaseServiceItem] = []
    @Published public var vulnerabilities: [VulnerabilityItem] = []
    @Published public var auditState: AuditState = .notRun
    /// Raw results of the last full audit and of each project folder audited by hand, before ignore filters.
    private var globalAuditVulns: [VulnerabilityItem] = []
    private var globalAuditFailed = 0
    private var projectAuditVulns: [String: [VulnerabilityItem]] = [:]
    private var projectAuditFailed: [String: Int] = [:]
    
    @Published public var isScanning: Bool = false
    @Published public var isAuditingSecurity: Bool = false
    @Published public var isActionRunning: Bool = false
    @Published public var currentActionPackageId: String? = nil
    /// True while `currentActionPackageId` is being removed rather than upgraded.
    @Published public var currentActionIsUninstall = false
    @Published public var actionProgress: Double = 0.0
    @Published public var actionStage: String = ""
    @Published public var completedPackageId: String? = nil
    @Published public var fixingVulnId: String? = nil
    @Published public var uvTools: [PackageItem] = []
    /// Why the uv tool list may be empty: uv missing, listing failed, or genuinely no tools.
    @Published public var uvScanState: UVScanState = .unknown
    @Published public var pythonInterpreters: [PythonInterpreter] = []
    @Published public var isScanningPython: Bool = false
    @Published public var pythonActionLabel: String? = nil
    @Published public var availableManagers: Set<PythonSource> = []
    /// Number of vulnerabilities hidden because the user accepted the risk.
    @Published public var ignoredCount: Int = 0
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? DevKeeperInfo.version
    }()
    public static let appBuild: String = {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "dev"
    }()
    
    // Install Sheet control
    @Published public var showInstallSheet: Bool = false
    
    // GitHub Self-Update
    @Published public var appUpdateAvailable: Bool = false
    @Published public var latestAppVersion: String = DevKeeperInfo.version
    @Published public var appReleaseNotes: String = ""
    @Published public var appDownloadUrl: String? = nil
    
    // Background Periodic Timer (Runs every 30 minutes)
    private var backgroundTimer: Timer?
    
    public init() {
        Task { [weak self] in
            guard let self = self else { return }
            await self.scanPythonInterpreters()
            await self.loadSystemInfo()
            await self.scanAll()
            
            self.applyFileWatcherSetting()
            self.restartBackgroundTimer()
        }
    }
    
    private static func boolSetting(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
    
    /// Starts or stops the directory watcher according to the `enableFSEvents` preference.
    public func applyFileWatcherSetting() {
        guard Self.boolSetting("enableFSEvents") else {
            FileSystemWatcher.shared.stopWatching()
            return
        }
        FileSystemWatcher.shared.startWatching { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isActionRunning else { return }
                self.appendLog("偵測到系統目錄變更，自動重新整理套件狀態...")
                await self.scanAll()
            }
        }
    }
    
    /// Restarts the periodic scan using the `scanIntervalMinutes` preference (default 30).
    public func restartBackgroundTimer() {
        backgroundTimer?.invalidate()
        let stored = UserDefaults.standard.integer(forKey: "scanIntervalMinutes")
        let minutes = stored > 0 ? stored : 30
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, !self.isActionRunning else { return }
                self.appendLog("執行定時背景掃描檢查 (每 \(minutes) 分鐘)...")
                await self.scanAll()
            }
        }
    }
    
    public var outdatedAIToolCount: Int {
        aiTools.filter { $0.isOutdated }.count
    }
    
    public var outdatedNpmCount: Int {
        npmPackages.filter { $0.status.isOutdated }.count
    }
    
    public var outdatedUVCount: Int {
        uvTools.filter { $0.status.isOutdated }.count
    }
    
    public var outdatedPythonCount: Int {
        pythonPackages.filter { $0.status.isOutdated }.count
    }
    
    public var outdatedBrewCount: Int {
        brewPackages.filter { $0.status.isOutdated }.count
    }
    
    public var vulnerabilityCount: Int {
        vulnerabilities.count
    }
    
    public var groupedVulnerabilities: [PackageVulnerabilityGroup] {
        PackageVulnerabilityGroup.grouped(from: vulnerabilities)
    }
    
    public var totalOutdatedCount: Int {
        outdatedAIToolCount + outdatedNpmCount + outdatedPythonCount + outdatedUVCount + outdatedBrewCount
    }
    
    public func loadSystemInfo() async {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        
        let nodeVer = (try? await ShellExecutor.shared.run(command: "node --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        let npmVer = (try? await ShellExecutor.shared.run(command: "npm --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        let pyVer = (try? await ShellExecutor.shared.run(command: "\(PythonRuntime.executable) --version"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        let brewVer = (try? await ShellExecutor.shared.run(command: "brew --version | head -n 1"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "未安裝"
        
        let nodePath = (try? await ShellExecutor.shared.run(command: "command -v node"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let npmPath = (try? await ShellExecutor.shared.run(command: "command -v npm"))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        self.systemInfo = SystemInfo(
            osVersion: os,
            nodeVersion: nodeVer,
            npmVersion: npmVer,
            pythonVersion: pyVer,
            brewVersion: brewVer,
            nodePath: nodePath,
            npmPath: npmPath
        )
    }
    
    public func scanAll() async {
        guard !isScanning else { return }
        isScanning = true
        appendLog("開始掃描系統安裝之所有套件、AI 工具與服務狀態...")
        
        async let aiTask = scanAITools()
        async let npmTask = scanNpm()
        async let pyTask = scanPython()
        async let uvTask = scanUV()
        async let brewTask = scanBrew()
        async let dbTask = scanDatabases()
        async let selfUpdateTask: Void = checkSelfUpdateIfEnabled()
        
        _ = await (aiTask, npmTask, pyTask, uvTask, brewTask, dbTask, selfUpdateTask)
        
        self.lastScanDate = Date()
        self.isScanning = false
        appendLog("掃描完成。發現 \(totalOutdatedCount) 個待更新項目。")
        
        if Self.boolSetting("enableSecurityAudit") {
            Task { await self.scanSecurityAudit() }
        }
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
            appendLog("已取消 \(item.name) 更新：指令會執行遠端下載的腳本，需先確認。")
            return
        }
        isActionRunning = true
        currentActionPackageId = item.id
        
        appendLog("正在更新 AI 開發工具: \(item.name) (\(item.updateCommand))...")
        liveLogOutput = ""
        
        let stream = AIToolService.shared.upgradeTool(item: item)
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        let local = await AIToolService.shared.detectLocalTool(item: item)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let idx = self.aiTools.firstIndex(where: { $0.id == item.id }) {
                self.aiTools[idx].isInstalled = local.isInstalled
                self.aiTools[idx].currentVersion = local.version
                self.aiTools[idx].binaryPath = local.binaryPath
                if self.aiTools[idx].isOutdated {
                    appendLog("\(item.name) 更新後版本仍為 \(local.version)，低於最新版 \(item.latestVersion ?? "?")，更新可能未成功，請查看日誌。")
                } else {
                    appendLog("\(item.name) 更新完成，目前版本 \(local.version)。")
                }
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
    
    public func scanSecurityAudit() async {
        guard !isAuditingSecurity else { return }
        self.isAuditingSecurity = true
        appendLog("正在啟動全面安全弱點稽核 (Google OSV CVE/GHSA 比對)...")
        
        let outcome = await AuditEngine.auditOutcome(
            interpreters: pythonInterpreters,
            npmPackages: npmPackages.map { ($0.name, $0.currentVersion) },
            projectsRoot: UserDefaults.standard.string(forKey: "projectsRootPath")
        )
        globalAuditVulns = outcome.vulnerabilities
        globalAuditFailed = outcome.failed
        applyAuditResults()
        self.isAuditingSecurity = false
        
        if outcome.failed > 0 {
            appendLog("全面安全稽核未完成：\(outcome.failed) / \(outcome.checked) 個套件查詢 OSV 失敗，結果不完整。")
        } else if !vulnerabilities.isEmpty {
            appendLog("全面安全稽核完成：偵測到 \(vulnerabilities.count) 個已知安全性弱點 (CVE/GHSA)！")
        } else {
            appendLog("全面安全稽核完成：本機套件與開發專案均未發現已知 CVE 弱點。")
        }
    }
    
    /// Combines the last full audit with the project folders audited by hand, hides ignored risks and built-in
    /// exceptions, and refreshes the audit state.
    private func applyAuditResults() {
        var seen = Set<String>()
        var combined: [VulnerabilityItem] = []
        for v in globalAuditVulns + projectAuditVulns.values.flatMap({ $0 }) {
            let scope = v.environment?.pythonPath ?? v.projectPath ?? ""
            if seen.insert("\(v.id)|\(v.packageName.lowercased())|\(scope)").inserted { combined.append(v) }
        }
        let ignored = ignoredKeys
        let visible = combined.filter { !ignored.contains(Self.ignoreKey($0)) && !isBuiltInException($0) }
        self.ignoredCount = combined.count - visible.count
        self.vulnerabilities = visible
        
        // Keep failure reasons only for groups that are still present after the rescan.
        let stillPresent = Set(groupedVulnerabilities.map { $0.id })
        func isCurrent(_ key: String) -> Bool { stillPresent.contains { key.hasPrefix($0 + "|") } }
        self.fixFailures = self.fixFailures.filter { isCurrent($0.key) }
        self.remediationPlans = self.remediationPlans.filter { isCurrent($0.key) }
        self.remediationNotes = self.remediationNotes.filter { isCurrent($0.key) }
        
        let failed = globalAuditFailed + projectAuditFailed.values.reduce(0, +)
        auditState = failed > 0 ? .incomplete(failed: failed) : .complete
    }
    
    /// Drops fixed items from the visible list and from the stored results, so a later project audit does not
    /// bring them back before the next full audit.
    private func removeFromAuditResults(where shouldRemove: (VulnerabilityItem) -> Bool) {
        vulnerabilities.removeAll(where: shouldRemove)
        globalAuditVulns.removeAll(where: shouldRemove)
        for key in Array(projectAuditVulns.keys) {
            projectAuditVulns[key]?.removeAll(where: shouldRemove)
        }
    }
    
    /// Forgets every audit result, e.g. when the audit is turned off in Settings.
    public func clearSecurityResults() {
        globalAuditVulns = []
        globalAuditFailed = 0
        projectAuditVulns = [:]
        projectAuditFailed = [:]
        vulnerabilities = []
        ignoredCount = 0
        auditState = .notRun
    }
    
    // MARK: - Alternative fixes (remove / move to an isolated environment)
    
    /// Works out whether a vulnerable package can be removed, or its tool moved to an isolated environment.
    public func prepareRemediation(for group: PackageVulnerabilityGroup, environment env: PythonEnvironmentRef?) async {
        let key = group.key(for: env)
        remediationPlans[key] = nil
        remediationNotes[key] = nil
        guard let env, env.kind == .interpreter,
              let interpreter = pythonInterpreters.first(where: { $0.path == env.pythonPath }) else { return }
        switch await PythonEnvironmentService.shared.plan(
            packageName: group.packageName, interpreter: interpreter,
            targetPython: InterpreterChoice.migrationTarget(from: pythonInterpreters, uvAvailable: availableManagers.contains(.uv)),
            uvAvailable: availableManagers.contains(.uv)
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
        
        let result = await RemediationEngine.execute(
            plan,
            interpreters: pythonInterpreters,
            stage: { text in await MainActor.run { self.actionStage = text } },
            output: { text in await MainActor.run { self.liveLogOutput += text } },
            notice: { text in await MainActor.run { self.appendLog(text) } }
        )
        if case .failure(let reason) = result {
            remediationNotes[key] = reason
            return false
        }
        
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
    
    // MARK: - Accepted risks
    
    private static let ignoredKeysDefaults = "ignoredVulnerabilityKeys"
    
    /// An ignore applies to one package at one installed version in one place; upgrading it ends the ignore.
    private static func ignoreKey(_ v: VulnerabilityItem) -> String {
        "\(v.ecosystem.lowercased())|\(v.packageName.lowercased())@\(v.currentVersion)|\(v.environment?.pythonPath ?? v.projectPath ?? "")"
    }
    
    private var ignoredKeys: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.ignoredKeysDefaults) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.ignoredKeysDefaults) }
    }
    
    private static let showBuiltInExceptionsDefaults = "showBuiltInPythonExceptions"
    
    /// Built-in exception: pip, setuptools and wheel inside the OS-provided Python (the one Apple ships with
    /// Xcode / Command Line Tools). Users cannot upgrade that Python, and the fixed versions need a newer one,
    /// so these are hidden by default instead of showing an unfixable warning on every Mac with Xcode.
    private func isBuiltInException(_ v: VulnerabilityItem) -> Bool {
        guard !UserDefaults.standard.bool(forKey: Self.showBuiltInExceptionsDefaults) else { return false }
        return AuditEngine.isBuiltInException(v, interpreters: pythonInterpreters)
    }
    
    /// True when every environment of the group is the OS-provided Python's own pip/setuptools/wheel, which
    /// cannot be upgraded from here (the fixed versions need a newer Python than Apple ships).
    public func isSystemBuiltIn(_ group: PackageVulnerabilityGroup) -> Bool {
        let name = PythonDependencyGraph.normalize(group.packageName)
        guard PythonDependencyGraph.baseTooling.contains(name), !group.environments.isEmpty else { return false }
        return group.environments.allSatisfy { env in
            env.kind == .interpreter
                && pythonInterpreters.contains { $0.path == env.pythonPath && $0.source == .system }
        }
    }
    
    /// Hides a package's vulnerabilities in one environment (a known risk that cannot be fixed there).
    public func ignoreRisk(group: PackageVulnerabilityGroup, environment: PythonEnvironmentRef?) {
        let targets = vulnerabilities.filter {
            $0.packageName.lowercased() == group.packageName.lowercased()
                && $0.projectPath == group.projectPath && $0.environment == environment
        }
        guard !targets.isEmpty else { return }
        var keys = ignoredKeys
        for v in targets { keys.insert(Self.ignoreKey(v)) }
        ignoredKeys = keys
        withAnimation {
            vulnerabilities.removeAll { v in targets.contains { $0.id == v.id && $0.environment == v.environment && $0.packageName == v.packageName } }
        }
        ignoredCount += targets.count
        appendLog("已忽略 \(group.packageName)（\(environment?.label ?? "全域")）的 \(targets.count) 個已知風險。")
    }
    
    /// Shows every ignored risk again.
    public func restoreIgnoredRisks() async {
        ignoredKeys = []
        UserDefaults.standard.set(true, forKey: Self.showBuiltInExceptionsDefaults)
        ignoredCount = 0
        await scanSecurityAudit()
    }
    
    public func auditLocalProject(at url: URL) async {
        guard !isAuditingSecurity else { return }
        isAuditingSecurity = true
        appendLog("正在透過 Google OSV 審查本機網頁專案前後端相依套件安全漏洞: \(url.lastPathComponent)...")
        
        let outcome = await SecurityService.shared.auditProjectDirectoryOutcome(at: url)
        projectAuditVulns[url.path] = outcome.vulnerabilities
        projectAuditFailed[url.path] = outcome.failed
        // Only a finished full audit makes an empty list trustworthy; a project audit alone must not.
        if auditState == .notRun {
            applyAuditResultsKeepingState()
        } else {
            applyAuditResults()
        }
        
        if outcome.failed > 0 {
            appendLog("專案安全稽核未完成：\(url.lastPathComponent) 有 \(outcome.failed) 個套件查詢 OSV 失敗，結果不完整。")
        } else if !outcome.vulnerabilities.isEmpty {
            appendLog("專案安全稽核完成：在 \(url.lastPathComponent) 偵測到 \(outcome.vulnerabilities.count) 個安全性漏洞！")
        } else {
            appendLog("專案安全稽核完成：\(url.lastPathComponent) 未偵測到已知安全性弱點。")
        }
        self.isAuditingSecurity = false
    }
    
    /// Updates the visible list from the stored results without claiming that a full audit has run.
    private func applyAuditResultsKeepingState() {
        let state = auditState
        applyAuditResults()
        auditState = state
    }
    
    /// Runs a fix command and verifies the result by the installed version.
    private func executeFix(command: String, packageName: String, ecosystem: String, targetVersion: String?, environment: PythonEnvironmentRef? = nil) async -> FixOutcome {
        await FixEngine.execute(
            command: command,
            packageName: packageName,
            ecosystem: ecosystem,
            targetVersion: targetVersion,
            environment: environment,
            interpreters: pythonInterpreters,
            output: { text in await MainActor.run { self.liveLogOutput += text } },
            notice: { text in await MainActor.run { self.appendLog(text) } }
        )
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
                    self.removeFromAuditResults {
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
            self.removeFromAuditResults { $0.id == item.id }
        }
    }
    
    public func fixAllVulnerabilities() async {
        guard !isActionRunning, !vulnerabilities.isEmpty else { return }
        self.isActionRunning = true
        self.isFixingAllVulnerabilities = true
        self.actionStage = "準備批次修復已知弱點..."
        self.actionProgress = 0.05
        appendLog("啟動批次修復所有可更新之安全弱點...")
        
        let groups = groupedVulnerabilities.filter { !isSystemBuiltIn($0) }
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
    
    private func checkSelfUpdateIfEnabled() async {
        if Self.boolSetting("checkSelfUpdate") { await checkSelfUpdate() }
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
    }
    
    private func applySelectedPython() {
        // DevKeeper always uses the best supported interpreter; drop any selection saved by older versions.
        UserDefaults.standard.removeObject(forKey: PythonRuntime.selectedPathKey)
        PythonRuntime.setCurrent(automaticPython())
    }
    
    /// Picks a modern interpreter that pip may write to; the old system Python is used only as a last resort.
    private func automaticPython() -> PythonInterpreter? {
        InterpreterChoice.automatic(from: pythonInterpreters)
    }
    
    public var selectedPythonPath: String? { PythonRuntime.current?.path }
    
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
            
            // Second pass: descriptions and homepages from PyPI, for every package. Answers are cached on disk, so
            // only packages never seen before are fetched, outdated ones first.
            var cache = Self.loadPyPICache()
            applyPyPIInfo(cache)
            let missing = items.filter { cache[$0.name.lowercased()] == nil }
                .sorted { ($0.status.isOutdated ? 0 : 1) < ($1.status.isOutdated ? 0 : 1) }
                .prefix(80)
                .map(\.name)
            if !missing.isEmpty {
                let fetched = await PythonService.shared.fetchPyPIInfo(for: Array(missing))
                for (name, info) in fetched { cache[name.lowercased()] = info }
                savePyPICache(cache)
                applyPyPIInfo(cache)
            }
        } catch {
            appendLog("Python 套件掃描失敗: \(error.localizedDescription)")
        }
    }
    
    private static let pypiCacheKey = "pypiInfoCache"
    
    private static func loadPyPICache() -> [String: PythonService.PyPIInfo] {
        guard let data = UserDefaults.standard.data(forKey: pypiCacheKey),
              let cache = try? JSONDecoder().decode([String: PythonService.PyPIInfo].self, from: data) else { return [:] }
        return cache
    }
    
    /// Keeps the cache from growing without bound: past the cap, entries for packages no longer installed go.
    private static let pypiCacheLimit = 500
    
    private func savePyPICache(_ cache: [String: PythonService.PyPIInfo]) {
        var kept = cache
        if kept.count > Self.pypiCacheLimit {
            let installed = Set((pythonPackages + uvTools).map { $0.name.lowercased() })
            kept = kept.filter { installed.contains($0.key) }
        }
        if let data = try? JSONEncoder().encode(kept) { UserDefaults.standard.set(data, forKey: Self.pypiCacheKey) }
    }
    
    private func applyPyPIInfo(_ cache: [String: PythonService.PyPIInfo]) {
        for index in pythonPackages.indices {
            guard let info = cache[pythonPackages[index].name.lowercased()] else { continue }
            if pythonPackages[index].description == nil { pythonPackages[index].description = info.summary }
            if pythonPackages[index].homepage == nil { pythonPackages[index].homepage = info.homepage }
        }
        for index in uvTools.indices {
            guard let info = cache[uvTools[index].name.lowercased()] else { continue }
            // The uv notes (extras, Python) are kept after the PyPI summary.
            let notes = uvTools[index].description
            if let summary = info.summary, !(notes ?? "").hasPrefix(summary) {
                uvTools[index].description = notes.map { "\(summary) · \($0)" } ?? summary
            }
            if uvTools[index].homepage == nil { uvTools[index].homepage = info.homepage }
        }
    }
    
    public func scanUV() async {
        switch await UVToolService.shared.scan() {
        case .notInstalled:
            uvTools = []
            uvScanState = .notInstalled
        case .failed:
            uvScanState = .failed
            appendLog("uv 工具清單讀取失敗。")
        case .tools(let tools, let latestKnown):
            uvTools = tools.map { tool in
                var item = PackageItem(name: tool.name, currentVersion: tool.version, latestVersion: tool.latest, type: .uvTool)
                if !latestKnown {
                    item.status = .error
                } else if let latest = tool.latest {
                    if tool.isPinned {
                        item.status = .upToDate
                        item.pinnedSpecifier = tool.required
                    } else {
                        item.status = PackageItem.computeUpdateStatus(current: tool.version, latest: latest)
                    }
                } else {
                    item.status = .upToDate
                    item.latestVersion = tool.version
                }
                var notes: [String] = []
                if !tool.extras.isEmpty { notes.append("附加套件 \(tool.extras.joined(separator: ", "))") }
                if !tool.with.isEmpty { notes.append("另裝 \(tool.with.joined(separator: ", "))") }
                if let python = tool.python { notes.append(python) }
                item.description = notes.isEmpty ? nil : notes.joined(separator: " · ")
                return item
            }
            uvScanState = latestKnown ? .ready : .readyWithoutUpdateStatus
            applyPyPIInfo(Self.loadPyPICache())
            let cache = Self.loadPyPICache()
            let missing = uvTools.filter { cache[$0.name.lowercased()] == nil }.map(\.name).prefix(40)
            if !missing.isEmpty {
                var updated = cache
                for (name, info) in await PythonService.shared.fetchPyPIInfo(for: Array(missing)) { updated[name.lowercased()] = info }
                savePyPICache(updated)
                applyPyPIInfo(updated)
            }
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
        currentActionIsUninstall = false
        completedPackageId = nil
        actionProgress = 0.15
        actionStage = "準備更新環境..."
        
        appendLog("正在更新: \(package.name)...")
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
        case .uvTool:
            stream = UVToolService.shared.upgradeTool(name: package.name)
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
            appendLog("\(package.name) 更新失敗，請查看日誌。")
            self.isActionRunning = false
            self.currentActionPackageId = nil
            self.actionProgress = 0.0
            self.actionStage = ""
            return
        }
        
        if package.type == .uvTool {
            // uv exits 0 even when it did nothing (a pinned or range-limited tool), so check the version.
            self.actionStage = "確認更新結果..."
            await scanUV()
            let after = uvTools.first { $0.name == package.name }
            if after?.currentVersion == package.currentVersion {
                appendLog("\(package.name) 沒有更新：安裝時指定了版本或範圍，已是限制內的最新版。要換版本請重新安裝。")
                self.isActionRunning = false
                self.currentActionPackageId = nil
                self.actionProgress = 0.0
                self.actionStage = ""
                return
            }
            if let problems = await UVToolService.shared.dependencyProblems(name: package.name) {
                appendLog("\(package.name) 更新後相依套件有衝突：\(problems)")
            }
        }
        
        // Mark 100% completed
        self.actionProgress = 1.0
        self.actionStage = "更新完成！"
        self.completedPackageId = package.id
        appendLog("\(package.name) 更新程序完成。")
        
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
        case .uvTool:
            // Already refreshed from uv after the update.
            break
        }
    }
    
    public func cleanUninstall(package: PackageItem) async {
        guard !isActionRunning else { return }
        isActionRunning = true
        currentActionPackageId = package.id
        currentActionIsUninstall = true
        
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
        case .uvTool:
            stream = UVToolService.shared.uninstallTool(name: package.name)
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
            case .uvTool:
                self.uvTools.removeAll { $0.id == package.id || $0.name == package.name }
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
        case .uvTool:
            stream = UVToolService.shared.installTool(name: cleanName)
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
        appendLog("正在批次更新全域 npm 套件...")
        liveLogOutput = ""
        
        let stream = NpmService.shared.upgradeAll(packages: outdated.map { $0.name })
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("全域 npm 批次更新完成。")
        self.isActionRunning = false
        await scanNpm()
    }
    
    /// Outdated Homebrew formulae and casks shown in the list; only these are upgraded.
    public var outdatedBrewNames: (formulae: [String], casks: [String]) {
        let outdated = brewPackages.filter { $0.status.isOutdated }
        return (outdated.filter { $0.type == .brewFormula }.map(\.name), outdated.filter { $0.type == .brewCask }.map(\.name))
    }
    
    /// Exact commands run by "upgrade npm and Homebrew"; listed in confirmation panels before running.
    public var upgradeAllCommands: [String] {
        var commands: [String] = []
        if let npm = NpmService.upgradeAllCommand(packages: npmPackages.filter { $0.status.isOutdated }.map(\.name)) {
            commands.append(npm)
        }
        let brew = outdatedBrewNames
        commands.append(contentsOf: BrewService.upgradeCommands(formulae: brew.formulae, casks: brew.casks) ?? [])
        return commands
    }
    
    public func upgradeAllOutdatedBrew() async {
        guard !isActionRunning else { return }
        let names = outdatedBrewNames
        guard !names.formulae.isEmpty || !names.casks.isEmpty else { return }
        isActionRunning = true
        appendLog("正在更新 \(names.formulae.count + names.casks.count) 個 Homebrew 項目...")
        liveLogOutput = ""
        
        let stream = BrewService.shared.upgrade(formulae: names.formulae, casks: names.casks)
        for await chunk in stream {
            self.liveLogOutput += chunk
        }
        
        appendLog("Homebrew 更新完成。")
        self.isActionRunning = false
        await scanBrew()
    }
    
    private func refreshPackageType(_ type: PackageType) async {
        switch type {
        case .npm: await scanNpm()
        case .python: await scanPython()
        case .brewFormula, .brewCask: await scanBrew()
        case .uvTool: await scanUV()
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

import DevKeeperCore
import SwiftUI

public struct OverviewView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay

    @State private var filterCategory: CategoryFilter = .all
    @State private var filterScope: ScopeFilter = .all
    @State private var sortOption: SortOption = .outdatedness
    @State private var searchKeyword = ""

    enum CategoryFilter: Hashable { case all, brew, python, npm }
    enum ScopeFilter: Hashable { case all, major, minor, patch }
    enum SortOption: Hashable { case outdatedness, name, type }

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    /// Everything outdated that this page lists (AI tools have their own page).
    private var outdatedItems: [PackageItem] {
        (viewModel.npmPackages + viewModel.brewPackages + viewModel.pythonPackages).filter { $0.status.isOutdated }
    }

    private var isFiltering: Bool {
        filterCategory != .all || filterScope != .all || !searchKeyword.dkSearchKey.isEmpty
    }

    private var filteredOutdatedItems: [PackageItem] {
        let query = searchKeyword.dkSearchKey
        return outdatedItems.filter { item in
            switch filterCategory {
            case .all: break
            case .brew: if item.type != .brewFormula && item.type != .brewCask { return false }
            case .python: if item.type != .python { return false }
            case .npm: if item.type != .npm { return false }
            }
            switch filterScope {
            case .all: break
            case .major: if item.status != .major { return false }
            case .minor: if item.status != .minor { return false }
            case .patch: if item.status != .patch { return false }
            }
            if !query.isEmpty {
                let inName = item.name.lowercased().contains(query)
                let inDescription = item.description?.lowercased().contains(query) ?? false
                if !inName && !inDescription { return false }
            }
            return true
        }.sorted { a, b in
            switch sortOption {
            case .outdatedness:
                if rank(a) != rank(b) { return rank(a) > rank(b) }
                return a.name.lowercased() < b.name.lowercased()
            case .name:
                return a.name.lowercased() < b.name.lowercased()
            case .type:
                if a.type.rawValue != b.type.rawValue { return a.type.rawValue < b.type.rawValue }
                return a.name.lowercased() < b.name.lowercased()
            }
        }
    }

    private func rank(_ item: PackageItem) -> Int {
        switch item.status {
        case .major: return 3
        case .minor: return 2
        default: return 1
        }
    }

    /// What "upgrade npm and Homebrew" will touch; Python packages and AI tools are upgraded on their own pages.
    private var upgradableCount: Int {
        viewModel.outdatedNpmCount + viewModel.outdatedBrewCount
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: DK.Space.xl) {
                    notices
                    metrics
                    outdatedSection
                    environment
                }
                .padding(.horizontal, DK.pagePadding)
                .padding(.bottom, DK.pagePadding)
            }
        }
        .background(DK.background)
    }

    // MARK: - Header

    private var header: some View {
        DKPageHeader(
            "總覽",
            subtitle: viewModel.lastScanDate.map { "上次檢查 \(Self.dateFormatter.string(from: $0))" } ?? "尚未檢查",
            count: outdatedItems.isEmpty ? nil : "\(outdatedItems.count) 項可更新"
        ) {
            DKButton("安裝套件", systemImage: "plus") { viewModel.showInstallSheet = true }
                .disabled(viewModel.isActionRunning)
            DKButton("重新檢查", systemImage: "arrow.clockwise", isLoading: viewModel.isScanning) {
                Task { await viewModel.scanAll() }
            }
            .disabled(viewModel.isScanning || viewModel.isActionRunning)
            if upgradableCount > 0 {
                DKButton("更新 npm 與 Homebrew（\(upgradableCount)）", kind: .primary,
                         disabledReason: viewModel.isActionRunning || viewModel.isScanning ? "正在執行其他操作" : nil) {
                    confirmUpgradeAll()
                }
                .disabled(viewModel.isActionRunning || viewModel.isScanning)
            }
        }
    }

    private func confirmUpgradeAll() {
        overlay?.confirm(
            "更新 \(upgradableCount) 個項目？",
            message: "只更新清單上的 npm 與 Homebrew 項目。Python 套件與 AI 工具請在各自的頁面更新。",
            commands: viewModel.upgradeAllCommands,
            confirmTitle: "全部更新"
        ) {
            Task {
                await viewModel.upgradeAllOutdatedNpm()
                await viewModel.upgradeAllOutdatedBrew()
            }
        }
    }

    // MARK: - Notices

    @ViewBuilder
    private var notices: some View {
        if viewModel.appUpdateAvailable {
            notice(
                title: "DevKeeper \(viewModel.latestAppVersion) 已發布",
                message: "前往 GitHub 下載新版。",
                actionTitle: "查看新版"
            ) {
                if let url = InputValidator.httpsURL(viewModel.appDownloadUrl, allowedHosts: ["github.com"]) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
        if viewModel.vulnerabilityCount > 0 {
            notice(
                title: "發現 \(viewModel.vulnerabilityCount) 個已知安全弱點",
                message: "已安裝的套件有公開的弱點紀錄，建議到安全弱點頁處理。",
                actionTitle: "查看弱點",
                danger: true
            ) {
                viewModel.selectedTab = .security
            }
        }
    }

    private func notice(title: String, message: String, actionTitle: String, danger: Bool = false,
                        action: @escaping () -> Void) -> some View {
        HStack(spacing: DK.Space.m) {
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                Text(title)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(danger ? DK.danger : DK.textPrimary)
                Text(message)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
            }
            Spacer(minLength: DK.Space.m)
            DKButton(actionTitle, action: action)
        }
        .dkCard()
    }

    // MARK: - Metrics

    private var metrics: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DK.Space.s), count: 3), spacing: DK.Space.s) {
            sourceCard("AI 工具", source: .ai, total: viewModel.aiTools.count, outdated: viewModel.outdatedAIToolCount, tab: .aiTools)
            sourceCard("npm", source: .npm, total: viewModel.npmPackages.count, outdated: viewModel.outdatedNpmCount, tab: .npm)
            sourceCard("Python", source: .python, total: viewModel.pythonPackages.count, outdated: viewModel.outdatedPythonCount, tab: .python)
            sourceCard("Homebrew", source: .homebrew, total: viewModel.brewPackages.count, outdated: viewModel.outdatedBrewCount, tab: .brew)
            DKMetricCard(
                title: "資料庫服務",
                value: "\(viewModel.databaseServices.count)",
                caption: "已安裝",
                source: .database,
                action: { viewModel.selectedTab = .database }
            )
            DKMetricCard(
                title: "安全弱點",
                value: "\(viewModel.vulnerabilityCount)",
                caption: securityCaption,
                systemImage: "shield",
                valueColor: viewModel.vulnerabilityCount > 0 ? DK.danger : DK.textPrimary,
                action: { viewModel.selectedTab = .security }
            )
        }
    }

    private var securityCaption: String {
        if viewModel.isAuditingSecurity { return "稽核中…" }
        if viewModel.vulnerabilityCount > 0 { return "有已知弱點" }
        switch viewModel.auditState {
        case .notRun: return "尚未稽核"
        case .incomplete: return "稽核不完整"
        case .complete: return "沒有已知弱點"
        }
    }

    private func sourceCard(_ title: String, source: DKSource, total: Int, outdated: Int, tab: NavigationTab) -> some View {
        DKMetricCard(
            title: title,
            value: "\(total)",
            caption: outdated > 0 ? "\(outdated) 項可更新" : (total > 0 ? "全部最新" : nil),
            source: source,
            barValue: total > 0 ? Double(outdated) / Double(total) : 0,
            action: { viewModel.selectedTab = tab }
        )
    }

    // MARK: - Outdated list

    private var outdatedSection: some View {
        VStack(alignment: .leading, spacing: DK.Space.m) {
            DKSectionTitle(
                "待更新清單",
                trailing: outdatedItems.isEmpty ? nil : "顯示 \(filteredOutdatedItems.count) / 共 \(outdatedItems.count) 項"
            )
            if !outdatedItems.isEmpty {
                filters
            }
            list
        }
    }

    private var filters: some View {
        HStack(spacing: DK.Space.s) {
            DKDropdown(options: [
                (CategoryFilter.all, "全部來源"), (.npm, "npm"), (.python, "Python"), (.brew, "Homebrew")
            ], selection: $filterCategory)
            DKDropdown(options: [
                (ScopeFilter.all, "全部幅度"), (.major, "主要版本"), (.minor, "次要版本"), (.patch, "修補版本")
            ], selection: $filterScope)
            DKDropdown(options: [
                (SortOption.outdatedness, "落後最多優先"), (.name, "名稱"), (.type, "來源")
            ], selection: $sortOption, label: "排序")
            if isFiltering {
                DKButton("重設", kind: .ghost) {
                    filterCategory = .all
                    filterScope = .all
                    sortOption = .outdatedness
                    searchKeyword = ""
                }
            }
            Spacer(minLength: DK.Space.s)
            DKSearchField(placeholder: "搜尋待更新套件", text: $searchKeyword)
        }
    }

    @ViewBuilder
    private var list: some View {
        if outdatedItems.isEmpty {
            if viewModel.lastScanDate == nil {
                if viewModel.isScanning {
                    DKEmptyState(kind: .loading, title: "正在檢查本機套件…")
                        .dkCard(padding: 0)
                } else {
                    DKEmptyState(kind: .idle, title: "尚未檢查", message: "檢查後會在這裡列出可更新的套件。",
                                 actionTitle: "重新檢查", action: { Task { await viewModel.scanAll() } })
                        .dkCard(padding: 0)
                }
            } else {
                DKEmptyState(kind: .allCurrent, title: "全部都是最新版本",
                             message: "npm、Python 與 Homebrew 沒有待更新的項目。")
                    .dkCard(padding: 0)
            }
        } else if filteredOutdatedItems.isEmpty {
            DKEmptyState(kind: .empty, title: "沒有符合條件的項目", message: "調整篩選條件或清除搜尋文字。")
                .dkCard(padding: 0)
        } else {
            VStack(spacing: DK.Space.s) {
                ForEach(filteredOutdatedItems) { package in
                    PackageRow(
                        package: package,
                        isActionRunning: viewModel.currentActionPackageId == package.id && viewModel.isActionRunning,
                        onUpgrade: { Task { await viewModel.upgradeSingle(package: package) } },
                        onCleanUninstall: { Task { await viewModel.cleanUninstall(package: package) } }
                    )
                }
            }
        }
    }

    // MARK: - Environment

    private var environment: some View {
        VStack(alignment: .leading, spacing: DK.Space.m) {
            DKSectionTitle("執行環境")
            HStack(alignment: .top, spacing: DK.Space.xl) {
                envItem("Node.js", viewModel.systemInfo.nodeVersion,
                        detail: Self.installSource(path: viewModel.systemInfo.nodePath),
                        update: brewUpdate(named: "node"))
                envItem("npm", viewModel.systemInfo.npmVersion,
                        detail: Self.installSource(path: viewModel.systemInfo.npmPath),
                        update: viewModel.npmPackages.first { $0.name == "npm" }.flatMap(updateText))
                envItem("Python", viewModel.systemInfo.pythonVersion,
                        detail: currentPythonSource,
                        update: currentPythonFormula.flatMap { brewUpdate(named: $0) })
                envItem("Homebrew", viewModel.systemInfo.brewVersion, detail: nil, update: nil)
                Spacer(minLength: 0)
            }
            .dkCard()
        }
    }
    
    private func updateText(_ package: PackageItem) -> String? {
        guard package.status.isOutdated, let latest = package.latestVersion else { return nil }
        return "可更新至 \(latest)"
    }
    
    /// Update text for a Homebrew formula, only when that formula is the installed one.
    private func brewUpdate(named name: String) -> String? {
        viewModel.brewPackages.first { $0.type == .brewFormula && $0.name == name }.flatMap(updateText)
    }
    
    private var currentPython: PythonInterpreter? {
        viewModel.pythonInterpreters.first { $0.path == viewModel.selectedPythonPath }
    }
    
    private var currentPythonSource: String? { currentPython?.source.rawValue }
    
    /// The Homebrew formula behind the interpreter in use, e.g. `python@3.11`.
    private var currentPythonFormula: String? {
        guard let python = currentPython, python.source == .homebrew else { return nil }
        return "python@\(python.minorVersion)"
    }
    
    /// Names the tool that installed a binary, from its path.
    private static func installSource(path: String) -> String? {
        guard !path.isEmpty else { return nil }
        if path.contains("/.nvm/") { return "nvm" }
        if path.contains("/.fnm/") || path.contains("/fnm_multishells/") { return "fnm" }
        if path.hasPrefix("/opt/homebrew/") || path.hasPrefix("/usr/local/") { return "Homebrew" }
        if path.hasPrefix("/usr/bin/") { return "系統內建" }
        return nil
    }
    
    private func envItem(_ label: String, _ value: String, detail: String?, update: String?) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.xxs) {
            Text(label)
                .font(DK.Font.caption)
                .foregroundColor(DK.textTertiary)
            Text(value.isEmpty ? "未安裝" : value)
                .font(DK.Font.mono)
                .foregroundColor(DK.textPrimary)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textTertiary)
            }
            if let update {
                Text(update)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.accent)
            }
        }
    }
    
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

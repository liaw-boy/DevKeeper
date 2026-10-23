import SwiftUI

public struct OverviewView: View {
    @ObservedObject var viewModel: AppViewModel
    
    // Filtering and sorting state for outdated list
    @State private var filterCategory: CategoryFilter = .all
    @State private var filterScope: ScopeFilter = .all
    @State private var sortOption: SortOption = .outdatedness
    @State private var searchKeyword: String = ""
    
    enum CategoryFilter: String, CaseIterable, Identifiable {
        case all = "全部生態"
        case brew = "Homebrew"
        case python = "Python pip"
        case npm = "npm 全域"
        
        var id: String { rawValue }
    }
    
    enum ScopeFilter: String, CaseIterable, Identifiable {
        case all = "全部更新幅度"
        case major = "重大更新 (Major)"
        case minor = "次要更新 (Minor)"
        case patch = "修補更新 (Patch)"
        
        var id: String { rawValue }
    }
    
    enum SortOption: String, CaseIterable, Identifiable {
        case outdatedness = "依過舊程度 (重大更新優先)"
        case name = "依套件名稱 (A-Z)"
        case type = "依生態類別"
        
        var id: String { rawValue }
    }
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredOutdatedItems: [PackageItem] {
        let all = (viewModel.npmPackages + viewModel.brewPackages + viewModel.pythonPackages).filter { $0.status.isOutdated }
        
        return all.filter { item in
            // Category filter
            switch filterCategory {
            case .all: break
            case .brew:
                if item.type != .brewFormula && item.type != .brewCask { return false }
            case .python:
                if item.type != .python { return false }
            case .npm:
                if item.type != .npm { return false }
            }
            
            // Scope filter
            if filterScope != .all {
                let scope = computeUpdateScope(for: item)
                if scope != filterScope { return false }
            }
            
            // Search keyword
            if !searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = searchKeyword.lowercased()
                let nameMatch = item.name.lowercased().contains(q)
                let descMatch = item.description?.lowercased().contains(q) ?? false
                if !nameMatch && !descMatch { return false }
            }
            
            return true
        }.sorted { a, b in
            switch sortOption {
            case .outdatedness:
                let scopeA = computeUpdateScope(for: a)
                let scopeB = computeUpdateScope(for: b)
                let rankA = (scopeA == .major ? 3 : (scopeA == .minor ? 2 : 1))
                let rankB = (scopeB == .major ? 3 : (scopeB == .minor ? 2 : 1))
                if rankA != rankB { return rankA > rankB }
                return a.name.lowercased() < b.name.lowercased()
                
            case .name:
                return a.name.lowercased() < b.name.lowercased()
                
            case .type:
                return a.type.rawValue < b.type.rawValue
            }
        }
    }
    
    private func computeUpdateScope(for pkg: PackageItem) -> ScopeFilter {
        guard let latest = pkg.latestVersion else { return .patch }
        let cParts = pkg.currentVersion.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).components(separatedBy: ".")
        let lParts = latest.trimmingCharacters(in: CharacterSet(charactersIn: "vV ")).components(separatedBy: ".")
        
        let cMajor = Int(cParts.first ?? "0") ?? 0
        let lMajor = Int(lParts.first ?? "0") ?? 0
        if lMajor > cMajor { return .major }
        
        if cParts.count > 1 && lParts.count > 1 {
            let cMinor = Int(cParts[1]) ?? 0
            let lMinor = Int(lParts[1]) ?? 0
            if lMinor > cMinor { return .minor }
        }
        
        return .patch
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Header Area
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "gauge")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(Theme.primaryIndigo)
                            Text("系統套件總覽")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        if let lastScan = viewModel.lastScanDate {
                            Text("上次檢查時間: \(lastScan, formatter: dateFormatter)")
                                .font(.system(size: 11.5))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        } else {
                            Text("正在分析本機套件與依賴狀態...")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 10) {
                        Button(action: { viewModel.showInstallSheet = true }) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("安裝套件")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.bouncy)
                        .disabled(viewModel.isActionRunning)
                        
                        Button(action: {
                            Task { await viewModel.scanAll() }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("重新檢查")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .padding(.horizontal, 11)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.bouncy)
                        .disabled(viewModel.isScanning || viewModel.isActionRunning)
                        
                        if viewModel.totalOutdatedCount > 0 {
                            Button(action: {
                                Task {
                                    await viewModel.upgradeAllOutdatedNpm()
                                    await viewModel.upgradeAllOutdatedBrew()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .font(.system(size: 11.5, weight: .bold))
                                    HStack(spacing: 0) {
                                        Text("全部升級 (")
                                        Text("\(viewModel.totalOutdatedCount)")
                                            .monospacedDigit()
                                        Text(")")
                                    }
                                    .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 13)
                                .padding(.vertical, 6)
                                .background(Theme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .shadow(color: Theme.primaryIndigo.opacity(0.4), radius: 6, x: 0, y: 2)
                            }
                            .buttonStyle(.bouncy)
                            .disabled(viewModel.isActionRunning || viewModel.isScanning)
                        }
                    }
                }
                
                // GitHub Self-Update Banner
                if viewModel.appUpdateAvailable {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("DevKeeper v\(viewModel.latestAppVersion) 最新版本已發布！")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Text("包含最新功能更新與效能提升，建議前往 GitHub 下載最新版本。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        if let url = InputValidator.httpsURL(viewModel.appDownloadUrl, allowedHosts: ["github.com"]) {
                            Link(destination: url) {
                                HStack(spacing: 5) {
                                    Image(systemName: "arrow.down.circle")
                                        .font(.system(size: 11.5, weight: .bold))
                                    Text("查看新版")
                                        .font(.system(size: 11.5, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.primaryGradient)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.bouncy)
                        }
                    }
                    .padding(12)
                    .background(Theme.primaryIndigo.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.primaryIndigo.opacity(0.3), lineWidth: 1)
                    )
                }
                
                // Security Alert Banner if vulnerabilities found
                if viewModel.vulnerabilityCount > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 18))
                            .foregroundColor(Theme.dangerRed)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("安全警報：偵測到 \(viewModel.vulnerabilityCount) 個安全性弱點 (CVE)！")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.primary)
                            Text("已透過 Google OSV 資料庫發現已安裝套件存在已知安全漏洞，建議前往安全弱點稽核檢視並立即修復。")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.12)) {
                                viewModel.selectedTab = .security
                            }
                        }) {
                            Text("查看弱點清單")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Theme.dangerRed)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.bouncy)
                    }
                    .padding(12)
                    .background(Theme.dangerRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.dangerRed.opacity(0.35), lineWidth: 1)
                    )
                }
                
                // MARK: - Redesigned Space-Efficient Compact Metric Grid (2 Rows x 4 Columns)
                // Height is reduced from ~360pt down to ~95pt, liberating over 260pt of vertical space!
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 8) {
                    compactMetricCard(
                        title: "AI 開發工具",
                        count: viewModel.aiTools.count,
                        outdated: viewModel.outdatedAIToolCount,
                        symbol: "sparkles",
                        tint: Theme.primaryIndigo,
                        tab: .aiTools
                    )
                    
                    compactMetricCard(
                        title: "npm 全域工具",
                        count: viewModel.npmPackages.count,
                        outdated: viewModel.outdatedNpmCount,
                        symbol: "cube",
                        tint: Theme.infoCyan,
                        tab: .npm
                    )
                    
                    compactMetricCard(
                        title: "Python (pip)",
                        count: viewModel.pythonPackages.count,
                        outdated: viewModel.outdatedPythonCount,
                        symbol: "chevron.left.forwardslash.chevron.right",
                        tint: Theme.successGreen,
                        tab: .python
                    )
                    
                    compactMetricCard(
                        title: "Homebrew",
                        count: viewModel.brewPackages.count,
                        outdated: viewModel.outdatedBrewCount,
                        symbol: "shippingbox",
                        tint: Theme.warningAmber,
                        tab: .brew
                    )
                    
                    compactMetricCard(
                        title: "資料庫服務",
                        count: viewModel.databaseServices.count,
                        outdated: 0,
                        symbol: "cylinder.split.1x2",
                        tint: Theme.purpleAccent,
                        tab: .database
                    )
                    
                    compactMetricCard(
                        title: "安全弱點 (CVE)",
                        count: viewModel.vulnerabilities.count,
                        outdated: viewModel.vulnerabilities.count,
                        symbol: "shield.checkered",
                        tint: viewModel.vulnerabilities.isEmpty ? Theme.successGreen : Theme.dangerRed,
                        tab: .security
                    )
                    
                    compactMetricCard(
                        title: "待升級總覽",
                        count: viewModel.totalOutdatedCount,
                        outdated: viewModel.totalOutdatedCount,
                        symbol: "bolt.fill",
                        tint: Theme.warningAmber,
                        tab: .overview
                    )
                }
                
                // MARK: - Outdated Packages Quick Action List with Multi-Dimensional Filters
                VStack(alignment: .leading, spacing: 12) {
                    // Title Row
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "square.stack.3d.up.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.warningAmber)
                            Text("待升級清單")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        Spacer()
                        
                        if viewModel.totalOutdatedCount > 0 {
                            Text("顯示 \(filteredOutdatedItems.count) / 全系統 \(viewModel.totalOutdatedCount) 個可升級項目")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Custom Styled Filter & Sort Toolbar (Replacing standard macOS system popups)
                    HStack(spacing: 8) {
                        // Category Menu
                        Menu {
                            ForEach(CategoryFilter.allCases) { cat in
                                Button(action: { filterCategory = cat }) {
                                    if filterCategory == cat {
                                        Label(cat.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(cat.rawValue)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(filterCategory != .all ? Theme.primaryIndigo : .secondary)
                                Text(filterCategory.rawValue)
                                    .font(.system(size: 11.5, weight: filterCategory != .all ? .semibold : .medium))
                                    .foregroundColor(filterCategory != .all ? .white : .primary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(filterCategory != .all ? Theme.primaryIndigo.opacity(0.14) : Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(filterCategory != .all ? Theme.primaryIndigo.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Scope Menu (Major, Minor, Patch)
                        Menu {
                            ForEach(ScopeFilter.allCases) { sc in
                                Button(action: { filterScope = sc }) {
                                    if filterScope == sc {
                                        Label(sc.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(sc.rawValue)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "bolt")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(filterScope != .all ? Theme.warningAmber : .secondary)
                                Text(filterScope.rawValue)
                                    .font(.system(size: 11.5, weight: filterScope != .all ? .semibold : .medium))
                                    .foregroundColor(filterScope != .all ? .white : .primary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(filterScope != .all ? Theme.warningAmber.opacity(0.14) : Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(filterScope != .all ? Theme.warningAmber.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Sort Option Menu
                        Menu {
                            ForEach(SortOption.allCases) { so in
                                Button(action: { sortOption = so }) {
                                    if sortOption == so {
                                        Label(so.rawValue, systemImage: "checkmark")
                                    } else {
                                        Text(so.rawValue)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .font(.system(size: 10.5))
                                    .foregroundColor(sortOption != .outdatedness ? Theme.infoCyan : .secondary)
                                Text(sortOption.rawValue)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.primary)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.secondary.opacity(0.8))
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.subtleBorder, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        // Reset button if any filter active
                        if filterCategory != .all || filterScope != .all || !searchKeyword.isEmpty {
                            Button(action: {
                                withAnimation(.easeOut(duration: 0.12)) {
                                    filterCategory = .all
                                    filterScope = .all
                                    sortOption = .outdatedness
                                    searchKeyword = ""
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 9.5))
                                    Text("重設")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .frame(height: 28)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Theme.subtleBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .help("重設所有篩選條件")
                        }
                        
                        Spacer()
                        
                        // Search Box (Unified 28pt height)
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("搜尋待升級套件名稱...", text: $searchKeyword)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11.5))
                            if !searchKeyword.isEmpty {
                                Button(action: { searchKeyword = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .frame(width: 190, height: 28)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                    }
                    .padding(.vertical, 2)
                    
                    // Outdated List Cards
                    if filteredOutdatedItems.isEmpty {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: viewModel.totalOutdatedCount == 0 ? "checkmark.circle.fill" : "line.3.horizontal.decrease.circle")
                                    .font(.system(size: 26))
                                    .foregroundColor(viewModel.totalOutdatedCount == 0 ? Theme.successGreen : .secondary.opacity(0.6))
                                Text(viewModel.totalOutdatedCount == 0 ? "所有開發套件均為最新版本" : "沒有符合目前篩選條件的項目")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Text(viewModel.totalOutdatedCount == 0 ? "開發環境保持最新狀態，無待升級項目" : "請嘗試切換更新幅度、生態分類或清除搜尋關鍵字")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 32)
                            Spacer()
                        }
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                    } else {
                        VStack(spacing: 8) {
                            ForEach(filteredOutdatedItems) { package in
                                PackageRow(
                                    package: package,
                                    isActionRunning: viewModel.currentActionPackageId == package.id,
                                    onUpgrade: {
                                        Task { await viewModel.upgradeSingle(package: package) }
                                    },
                                    onCleanUninstall: {
                                        Task { await viewModel.cleanUninstall(package: package) }
                                    }
                                )
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.98)),
                                        removal: .scale(scale: 0.92, anchor: .center)
                                            .combined(with: .opacity)
                                            .combined(with: .offset(x: 35))
                                    )
                                )
                            }
                        }
                    }
                }
                
                // Environment Info Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("開發執行環境資訊")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    HStack(spacing: 12) {
                        envBadge(label: "Node.js", value: viewModel.systemInfo.nodeVersion)
                        envBadge(label: "npm", value: viewModel.systemInfo.npmVersion)
                        envBadge(label: "Python", value: viewModel.systemInfo.pythonVersion)
                        envBadge(label: "Homebrew", value: viewModel.systemInfo.brewVersion)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
        }
    }
    
    // MARK: - Ultra-Compact Metric Card (~46pt height)
    private func compactMetricCard(
        title: String,
        count: Int,
        outdated: Int,
        symbol: String,
        tint: Color,
        tab: NavigationTab
    ) -> some View {
        Button(action: {
            withAnimation(.easeOut(duration: 0.12)) {
                viewModel.selectedTab = tab
            }
        }) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(tint)
                }
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Text("\(count)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
                
                Spacer(minLength: 4)
                
                if outdated > 0 {
                    Text("\(outdated) 待更")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Theme.warningAmber)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.warningAmber.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bouncy(scale: 0.98))
    }
    
    private func envBadge(label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Text(label + ":")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "未安裝" : value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }
}

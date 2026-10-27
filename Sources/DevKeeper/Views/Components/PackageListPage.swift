import DevKeeperCore
import SwiftUI

/// What "upgrade all" runs on a package page. `commands` are listed in the confirmation panel.
struct PackageUpgradeAll {
    let commands: [String]
    let action: () async -> Void
}

/// The shared page for npm, Python and Homebrew: header, search, filters and a list of `PackageRow`s.
struct PackageListPage<Extra: View>: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay
    
    let title: String
    let subtitle: String
    let noun: String
    let notice: String?
    let packages: [PackageItem]
    let outdatedCount: Int
    let upgradeAll: PackageUpgradeAll?
    /// Page-specific filtering applied on top of search and "outdated only".
    let extraFilter: (PackageItem) -> Bool
    let extraControls: Extra
    
    @State private var searchText = ""
    @State private var onlyOutdated = false
    
    init(viewModel: AppViewModel, title: String, subtitle: String, noun: String, notice: String? = nil, packages: [PackageItem],
         outdatedCount: Int, upgradeAll: PackageUpgradeAll? = nil,
         extraFilter: @escaping (PackageItem) -> Bool = { _ in true },
         @ViewBuilder extraControls: () -> Extra) {
        self.viewModel = viewModel
        self.title = title
        self.subtitle = subtitle
        self.noun = noun
        self.notice = notice
        self.packages = packages
        self.outdatedCount = outdatedCount
        self.upgradeAll = upgradeAll
        self.extraFilter = extraFilter
        self.extraControls = extraControls()
    }
    
    private var filtered: [PackageItem] {
        let query = searchText.dkSearchKey
        return packages.filter { item in
            if onlyOutdated && !item.status.isOutdated { return false }
            if !query.isEmpty {
                let inName = item.name.lowercased().contains(query)
                let inDescription = item.description?.lowercased().contains(query) ?? false
                if !inName && !inDescription { return false }
            }
            return extraFilter(item)
        }
    }
    
    private var isBusy: Bool { viewModel.isActionRunning || viewModel.isScanning }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DKPageHeader(title, subtitle: subtitle,
                             count: outdatedCount > 0 ? "\(outdatedCount) 項可更新" : "\(packages.count) 個\(noun)") {
                    DKButton("安裝", systemImage: "plus") { viewModel.showInstallSheet = true }
                        .disabled(viewModel.isActionRunning)
                    DKButton("重新檢查", systemImage: "arrow.clockwise", isLoading: viewModel.isScanning) {
                        Task { await viewModel.scanAll() }
                    }
                    .disabled(isBusy)
                    if let upgradeAll, outdatedCount > 0 {
                        DKButton("全部更新（\(outdatedCount)）", kind: .primary,
                                 disabledReason: isBusy ? "正在執行其他操作" : nil) {
                            overlay?.confirm(
                                "更新 \(outdatedCount) 個\(noun)？",
                                message: "將執行以下指令。",
                                commands: upgradeAll.commands,
                                confirmTitle: "全部更新"
                            ) {
                                Task { await upgradeAll.action() }
                            }
                        }
                        .disabled(isBusy)
                    }
                }
                
                VStack(alignment: .leading, spacing: DK.Space.m) {
                    if let notice {
                        HStack(spacing: DK.Space.s) {
                            Image(systemName: "info.circle")
                                .font(.system(size: DK.Icon.regular))
                                .foregroundColor(DK.textSecondary)
                            Text(notice)
                                .font(DK.Font.caption)
                                .foregroundColor(DK.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .dkCard()
                    }
                    HStack(spacing: DK.Space.s) {
                        DKSearchField(placeholder: "搜尋\(noun)", text: $searchText)
                        Spacer(minLength: DK.Space.s)
                        extraControls
                        DKSegmented(options: [(false, "全部"), (true, "待更新 \(outdatedCount)")], selection: $onlyOutdated)
                    }
                    list
                }
                .padding(.horizontal, DK.pagePadding)
                .padding(.bottom, DK.pagePadding)
            }
        }
        .background(DK.background)
    }
    
    @ViewBuilder
    private var list: some View {
        if packages.isEmpty {
            if viewModel.isScanning || viewModel.lastScanDate == nil && viewModel.isScanning {
                DKEmptyState(kind: .loading, title: "正在檢查\(noun)與官方版本…").dkCard(padding: 0)
            } else if viewModel.lastScanDate == nil {
                DKEmptyState(kind: .idle, title: "尚未檢查", message: "檢查後會在這裡列出已安裝的\(noun)。",
                             actionTitle: "重新檢查", action: { Task { await viewModel.scanAll() } })
                    .dkCard(padding: 0)
            } else {
                DKEmptyState(kind: .empty, title: "沒有找到\(noun)").dkCard(padding: 0)
            }
        } else if filtered.isEmpty {
            if onlyOutdated && searchText.dkSearchKey.isEmpty {
                DKEmptyState(kind: .allCurrent, title: "全部都是最新版本").dkCard(padding: 0)
            } else {
                DKEmptyState(kind: .empty, title: "沒有符合條件的項目", message: "調整搜尋文字或篩選條件。").dkCard(padding: 0)
            }
        } else {
            LazyVStack(spacing: DK.Space.s) {
                ForEach(filtered) { item in
                    PackageRow(
                        package: item,
                        isActionRunning: viewModel.currentActionPackageId == item.id && viewModel.isActionRunning,
                        onUpgrade: { Task { await viewModel.upgradeSingle(package: item) } },
                        onCleanUninstall: { Task { await viewModel.cleanUninstall(package: item) } }
                    )
                }
            }
        }
    }
}

extension PackageListPage where Extra == EmptyView {
    init(viewModel: AppViewModel, title: String, subtitle: String, noun: String, notice: String? = nil,
         packages: [PackageItem], outdatedCount: Int, upgradeAll: PackageUpgradeAll? = nil) {
        self.init(viewModel: viewModel, title: title, subtitle: subtitle, noun: noun, notice: notice, packages: packages,
                  outdatedCount: outdatedCount, upgradeAll: upgradeAll, extraFilter: { _ in true }) { EmptyView() }
    }
}

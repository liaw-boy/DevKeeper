import DevKeeperCore
import SwiftUI

public struct MainView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    
    public init() {}
    
    public var body: some View {
        DKOverlayHost {
            HStack(spacing: 0) {
                Sidebar()
                    .frame(width: DK.sidebarWidth)
                Rectangle()
                    .fill(DK.border)
                    .frame(width: 1)
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(DK.background)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 1100, minHeight: 700)
        .sheet(isPresented: $viewModel.showInstallSheet) {
            InstallPackageSheet(viewModel: viewModel)
        }
    }
    
    @ViewBuilder
    private var detail: some View {
        switch viewModel.selectedTab {
        case .overview: OverviewView(viewModel: viewModel)
        case .aiTools: AIToolsView(viewModel: viewModel)
        case .npm: NpmListView(viewModel: viewModel)
        case .python: PythonListView(viewModel: viewModel)
        case .brew: BrewListView(viewModel: viewModel)
        case .database: DatabaseListView(viewModel: viewModel)
        case .security: SecurityAuditView(viewModel: viewModel)
        case .console: ConsoleView(viewModel: viewModel)
        case .settings: SettingsView(viewModel: viewModel)
        }
    }
}

extension NavigationTab {
    /// Short label used in the sidebar and menu bar panel.
    var title: String {
        switch self {
        case .overview: return "總覽"
        case .aiTools: return "AI 工具"
        case .npm: return "npm"
        case .python: return "Python"
        case .brew: return "Homebrew"
        case .database: return "資料庫"
        case .security: return "安全弱點"
        case .console: return "執行日誌"
        case .settings: return "設定"
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var viewModel: AppViewModel
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window's close/minimise/zoom buttons sit at the left of this row.
            HStack {
                Spacer()
                Text("DevKeeper")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textTertiary)
            }
            .frame(height: 28)
            .padding(.horizontal, DK.Space.l)
            .padding(.top, DK.Space.xs)
            .padding(.bottom, DK.Space.m)
            
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                item(.overview)
                section("套件")
                item(.aiTools, count: viewModel.outdatedAIToolCount)
                item(.npm, count: viewModel.outdatedNpmCount)
                item(.python, count: viewModel.outdatedPythonCount)
                item(.brew, count: viewModel.outdatedBrewCount)
                item(.database)
                section("安全")
                item(.security, count: viewModel.vulnerabilityCount, alert: true)
            }
            .padding(.horizontal, DK.Space.s)
            
            Spacer(minLength: DK.Space.l)
            
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                item(.console)
                item(.settings)
            }
            .padding(.horizontal, DK.Space.s)
            .padding(.bottom, DK.Space.s)
            
            DKDivider()
            statusLine
                .padding(.horizontal, DK.Space.l)
                .frame(height: 36)
        }
        .background(DK.surfaceSunken)
    }
    
    private func section(_ title: String) -> some View {
        Text(title)
            .font(DK.Font.micro)
            .foregroundColor(DK.textTertiary)
            .padding(.horizontal, DK.Space.s)
            .padding(.top, DK.Space.l)
            .padding(.bottom, DK.Space.xs)
    }
    
    private func item(_ tab: NavigationTab, count: Int = 0, alert: Bool = false) -> some View {
        SidebarItem(
            tab: tab,
            count: count,
            alert: alert,
            isSelected: viewModel.selectedTab == tab
        ) {
            viewModel.selectedTab = tab
        }
    }
    
    private var statusLine: some View {
        HStack(spacing: DK.Space.s) {
            if let busy = busyText {
                DKSpinner(size: 12)
                Text(busy)
            } else if let date = viewModel.lastScanDate {
                Text("上次檢查 \(Self.timeFormatter.string(from: date))")
            } else {
                Text("尚未檢查")
            }
            Spacer(minLength: 0)
        }
        .font(DK.Font.caption)
        .foregroundColor(DK.textTertiary)
        .lineLimit(1)
    }
    
    private var busyText: String? {
        if viewModel.isActionRunning { return "執行中…" }
        if viewModel.isScanning { return "檢查中…" }
        if viewModel.isAuditingSecurity { return "稽核弱點中…" }
        if viewModel.isScanningPython { return "偵測 Python 中…" }
        return nil
    }
}

private struct SidebarItem: View {
    let tab: NavigationTab
    let count: Int
    let alert: Bool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DK.Space.s) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: DK.Icon.regular))
                    .foregroundColor(isSelected ? DK.accent : DK.textSecondary)
                    .frame(width: 18)
                Text(tab.title)
                    .font(isSelected ? DK.Font.bodyMedium : DK.Font.body)
                    .foregroundColor(isSelected ? DK.textPrimary : DK.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DK.Space.s)
                if count > 0 {
                    Text("\(count)")
                        .font(DK.Font.caption)
                        .monospacedDigit()
                        .foregroundColor(alert ? DK.danger : DK.textTertiary)
                }
            }
            .padding(.horizontal, DK.Space.s)
            .frame(height: DK.controlHeight)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(isSelected ? DK.accentSubtle : (isHovering ? DK.surfaceHover : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .onHover { isHovering = $0 }
        .accessibilityLabel(count > 0 ? "\(tab.title)，\(count) 項" : tab.title)
    }
}

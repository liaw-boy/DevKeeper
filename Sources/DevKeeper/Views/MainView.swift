import DevKeeperCore
import SwiftUI

public struct MainView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    
    public init() {}
    
    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // App Branding Header (Exact same width & alignment as navigation cards below, moved upwards)
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Theme.primaryGradient)
                            .frame(width: 24, height: 24)
                            .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 4, x: 0, y: 1.5)
                        Image(systemName: "cube.fill")
                            .font(.system(size: 11.5, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .frame(width: 24, height: 24)
                    
                    Text("DevKeeper")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text("v\(AppViewModel.appVersion)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 12)
                
                // Navigation Items with generous, comfortable spacing
                VStack(spacing: 8) {
                    ForEach(NavigationTab.allCases) { tab in
                        sidebarItem(tab: tab)
                    }
                }
                .padding(.horizontal, 12)
                
                Spacer()
                
                // Bottom Real-time Status Card
                VStack(spacing: 0) {
                    Divider()
                        .background(Theme.subtleBorder)
                    
                    HStack(spacing: 8) {
                        if viewModel.isScanning || viewModel.isActionRunning {
                            ProgressView()
                                .controlSize(.small)
                            Text(viewModel.isActionRunning ? "正在執行操作..." : "正在同步狀態...")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        } else {
                            Circle()
                                .fill(Theme.successGreen)
                                .frame(width: 6.5, height: 6.5)
                            Text("就緒")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.11))
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            Group {
                switch viewModel.selectedTab {
                case .overview:
                    OverviewView(viewModel: viewModel)
                case .aiTools:
                    AIToolsView(viewModel: viewModel)
                case .npm:
                    NpmListView(viewModel: viewModel)
                case .python:
                    PythonListView(viewModel: viewModel)
                case .brew:
                    BrewListView(viewModel: viewModel)
                case .database:
                    DatabaseListView(viewModel: viewModel)
                case .security:
                    SecurityAuditView(viewModel: viewModel)
                case .console:
                    ConsoleView(viewModel: viewModel)
                case .settings:
                    SettingsView(viewModel: viewModel)
                }
            }
            .frame(minWidth: 900, minHeight: 640)
            .background(Theme.canvasBackground)
            .toolbar(.hidden, for: .windowToolbar)
            .ignoresSafeArea(.container, edges: .top)
        }
        .frame(minWidth: 1140, minHeight: 740)
        .sheet(isPresented: $viewModel.showInstallSheet) {
            InstallPackageSheet(viewModel: viewModel)
        }
    }
    
    private func sidebarItem(tab: NavigationTab) -> some View {
        let isSelected = viewModel.selectedTab == tab
        
        return Button(action: {
            withAnimation(.easeOut(duration: 0.12)) {
                viewModel.selectedTab = tab
            }
        }) {
            HStack(spacing: 11) {
                Image(systemName: tab.sfSymbol)
                    .font(.system(size: 16.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(isSelected ? Theme.primaryIndigo : .secondary)
                    .frame(width: 22, height: 22, alignment: .center)
                
                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .primary : .secondary)
                
                Spacer()
                
                // Outdated / Warning count badge with semantic color hierarchy
                if let count = badgeCount(for: tab), count > 0 {
                    let badgeTint: Color = {
                        if tab == .security { return Theme.dangerRed }
                        if tab == .overview { return Theme.warningAmber }
                        return Theme.primaryIndigo
                    }()
                    
                    Text("\(count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(badgeTint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeTint.opacity(0.14))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bouncy(scale: 0.98))
    }
    
    private func badgeCount(for tab: NavigationTab) -> Int? {
        switch tab {
        case .overview:
            return viewModel.totalOutdatedCount
        case .aiTools:
            return viewModel.outdatedAIToolCount
        case .npm:
            return viewModel.outdatedNpmCount
        case .python:
            return viewModel.outdatedPythonCount
        case .brew:
            return viewModel.outdatedBrewCount
        case .security:
            return viewModel.vulnerabilityCount
        case .database, .console, .settings:
            return nil
        }
    }
}

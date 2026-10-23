import SwiftUI
import AppKit

public struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var allOutdatedItems: [PackageItem] {
        (viewModel.npmPackages + viewModel.brewPackages + viewModel.pythonPackages).filter { $0.status.isOutdated }
    }
    
    /// Only npm and Homebrew are upgraded by the "upgrade all" action.
    private var upgradableCount: Int {
        viewModel.outdatedNpmCount + viewModel.outdatedBrewCount
    }
    
    public var body: some View {
        VStack(spacing: 12) {
            header
            summary
            categoryList
            if !allOutdatedItems.isEmpty {
                previewList
            }
            securityBar
            footer
        }
        .padding(14)
        .frame(width: 380)
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "cube.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
            
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("DevKeeper")
                        .font(.headline)
                    Text("v\(AppViewModel.appVersion)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(lastScanText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            if viewModel.isScanning {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 28, height: 28)
            } else {
                iconButton("arrow.clockwise", help: "立即重新掃描") {
                    Task { await viewModel.scanAll() }
                }
            }
            iconButton("macwindow", help: "開啟 DevKeeper 主視窗") {
                openMainWindow()
            }
        }
    }
    
    private var lastScanText: String {
        if let date = viewModel.lastScanDate {
            return "上次檢查 \(Self.timeFormatter.string(from: date))"
        }
        return "尚未檢查"
    }
    
    // MARK: - Summary
    
    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if viewModel.totalOutdatedCount > 0 {
                Text("\(viewModel.totalOutdatedCount)")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                Text("項可升級")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
                Text("所有項目均為最新")
                    .font(.title3)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }
    
    // MARK: - Categories
    
    private var categoryList: some View {
        VStack(spacing: 0) {
            categoryRow("sparkles", "AI 開發工具", total: viewModel.aiTools.count, outdated: viewModel.outdatedAIToolCount, tab: .aiTools)
            Divider().padding(.leading, 38)
            categoryRow("shippingbox", "Homebrew", total: viewModel.brewPackages.count, outdated: viewModel.outdatedBrewCount, tab: .brew)
            Divider().padding(.leading, 38)
            categoryRow("chevron.left.forwardslash.chevron.right", "Python pip", total: viewModel.pythonPackages.count, outdated: viewModel.outdatedPythonCount, tab: .python)
            Divider().padding(.leading, 38)
            categoryRow("arrow.down.circle", "GitHub 軟體與工具", total: viewModel.githubTools.count, outdated: viewModel.outdatedGitHubCount, tab: .github)
            Divider().padding(.leading, 38)
            categoryRow("cube", "npm 全域", total: viewModel.npmPackages.count, outdated: viewModel.outdatedNpmCount, tab: .npm)
        }
        .groupBox()
    }
    
    private func categoryRow(_ icon: String, _ title: String, total: Int, outdated: Int, tab: NavigationTab) -> some View {
        Button {
            openTab(tab)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                
                Text(title)
                    .font(.system(size: 13))
                
                Text("\(total)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
                
                Spacer()
                
                if outdated > 0 {
                    Text("\(outdated) 待升級")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.14), in: Capsule())
                } else {
                    Text("最新")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Preview
    
    private var previewList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(allOutdatedItems.prefix(4))) { item in
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(item.currentVersion)
                        .foregroundStyle(.secondary)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                    Text(item.latestVersion ?? "")
                        .foregroundStyle(.orange)
                }
                .font(.system(size: 11).monospacedDigit())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                
                if item.id != allOutdatedItems.prefix(4).last?.id {
                    Divider().padding(.leading, 10)
                }
            }
            
            if allOutdatedItems.count > 4 {
                Divider()
                Button {
                    openMainWindow()
                } label: {
                    Text("還有 \(allOutdatedItems.count - 4) 項，於主視窗查看")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .groupBox()
    }
    
    // MARK: - Security
    
    private var securityBar: some View {
        let count = viewModel.vulnerabilityCount
        return Button {
            if count > 0 { openTab(.security) } else { openMainWindow() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: count > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .foregroundStyle(count > 0 ? Color.red : Color.green)
                Text(count > 0 ? "偵測到 \(count) 個安全性弱點" : "本機無已知安全性弱點")
                    .font(.system(size: 12, weight: .medium))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .groupBox(tint: count > 0 ? .red : nil)
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack(spacing: 8) {
            if upgradableCount > 0 {
                Button {
                    Task {
                        await viewModel.upgradeAllOutdatedNpm()
                        await viewModel.upgradeAllOutdatedBrew()
                    }
                } label: {
                    Label("全部升級 (\(upgradableCount))", systemImage: "arrow.triangle.2.circlepath")
                        .monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(viewModel.isActionRunning)
                .help("升級 npm 與 Homebrew 的待升級項目")
            }
            
            Spacer()
            
            Menu {
                Button("設定", systemImage: "gearshape") { openTab(.settings) }
                Button("安全稽核", systemImage: "shield.checkered") { openTab(.security) }
                Divider()
                Button("結束 DevKeeper", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }
    
    // MARK: - Helpers
    
    private func iconButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.6), in: Circle())
        .help(help)
    }
    
    private func openMainWindow() {
        StatusBarController.shared?.closePopover()
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    private func openTab(_ tab: NavigationTab) {
        viewModel.selectedTab = tab
        openMainWindow()
    }
}

private extension View {
    func groupBox(tint: Color? = nil) -> some View {
        self
            .background((tint ?? Color.primary).opacity(tint == nil ? 0.05 : 0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            )
    }
}

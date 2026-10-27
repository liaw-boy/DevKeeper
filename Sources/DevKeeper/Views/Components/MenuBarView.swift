import AppKit
import DevKeeperCore
import SwiftUI

/// Content of the menu bar panel: what is outdated, known vulnerabilities, and quick actions.
public struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    var onClose: () -> Void = {}
    @State private var confirmingUpgrade = false
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
    
    public init(viewModel: AppViewModel, onClose: @escaping () -> Void = {}) {
        self.viewModel = viewModel
        self.onClose = onClose
    }
    
    private struct PreviewItem: Identifiable {
        let id: String
        let name: String
        let current: String
        let latest: String
    }
    
    /// Every outdated item, AI tools included, so the list matches the count in the menu bar.
    private var outdatedItems: [PreviewItem] {
        let tools = viewModel.aiTools.filter { $0.isOutdated }.map {
            PreviewItem(id: "ai:\($0.id)", name: $0.name, current: $0.currentVersion, latest: $0.latestVersion ?? "")
        }
        let packages = (viewModel.npmPackages + viewModel.pythonPackages + viewModel.brewPackages)
            .filter { $0.status.isOutdated }
            .map { PreviewItem(id: "\($0.type.rawValue):\($0.name)", name: $0.name, current: $0.currentVersion, latest: $0.latestVersion ?? "") }
        return tools + packages
    }
    
    private var upgradableCount: Int {
        viewModel.outdatedNpmCount + viewModel.outdatedBrewCount
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, DK.Space.l)
                .padding(.vertical, DK.Space.m)
            DKDivider()
            summary
                .padding(.horizontal, DK.Space.l)
                .padding(.top, DK.Space.m)
                .padding(.bottom, DK.Space.s)
            categories
                .padding(.horizontal, DK.Space.s)
            let items = outdatedItems
            if !items.isEmpty {
                DKDivider()
                    .padding(.top, DK.Space.s)
                preview(items)
                    .padding(.horizontal, DK.Space.l)
                    .padding(.vertical, DK.Space.s)
            }
            DKDivider()
                .padding(.top, items.isEmpty ? DK.Space.s : 0)
            footer
                .padding(.horizontal, DK.Space.l)
                .padding(.vertical, DK.Space.m)
        }
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .fill(DK.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .stroke(DK.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous))
    }
    
    // MARK: - Sections
    
    private var header: some View {
        HStack(spacing: DK.Space.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text("DevKeeper")
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                HStack(spacing: DK.Space.tight) {
                    if busy { DKSpinner(size: 10) }
                    Text(statusText)
                }
                .font(DK.Font.caption)
                .foregroundColor(DK.textTertiary)
                .lineLimit(1)
            }
            Spacer()
            // Text buttons: the panel has no overlay host, so icon-button tooltips would not show.
            DKButton("檢查", kind: .ghost) {
                Task { await viewModel.scanAll() }
            }
            .disabled(viewModel.isScanning || viewModel.isActionRunning)
            // Ghost buttons carry their own horizontal padding; pull the last one out so its label ends on the
            // same edge as the content below, matching the left side.
            DKButton("主視窗", kind: .ghost) { openMainWindow() }
                .padding(.trailing, -DK.Space.m)
        }
    }
    
    private var busy: Bool {
        viewModel.isScanning || viewModel.isActionRunning || viewModel.isAuditingSecurity
    }
    
    private var statusText: String {
        if viewModel.isActionRunning { return "執行中…" }
        if viewModel.isScanning { return "檢查中…" }
        if viewModel.isAuditingSecurity { return "稽核弱點中…" }
        if let date = viewModel.lastScanDate { return "上次檢查 \(Self.timeFormatter.string(from: date))" }
        return "尚未檢查"
    }
    
    private var summary: some View {
        let count = viewModel.totalOutdatedCount
        let vulnerabilities = viewModel.vulnerabilityCount
        return VStack(alignment: .leading, spacing: DK.Space.s) {
            HStack(alignment: .top, spacing: DK.Space.s) {
                DKMetricCard(
                    title: "可更新",
                    value: "\(count)",
                    caption: count > 0 ? nil : "全部最新",
                    systemImage: "arrow.up.circle",
                    barValue: totalPackageCount > 0 ? Double(count) / Double(totalPackageCount) : 0,
                    captionBelow: true,
                    action: { openTab(.overview) }
                )
                DKMetricCard(
                    title: "安全弱點",
                    value: "\(vulnerabilities)",
                    caption: vulnerabilities > 0 ? nil : securityCaption,
                    systemImage: "shield",
                    valueColor: vulnerabilities > 0 ? DK.danger : DK.textPrimary,
                    captionBelow: true,
                    action: { openTab(.security) }
                )
            }
            // Both cards take the height of the taller one.
            .fixedSize(horizontal: false, vertical: true)
            if vulnerabilities > 0 {
                DKSegmentBar(segments: severitySegments)
            }
        }
    }
    
    private var securityCaption: String {
        if viewModel.isAuditingSecurity { return "稽核中…" }
        switch viewModel.auditState {
        case .notRun: return "尚未稽核"
        case .incomplete: return "稽核不完整"
        case .complete: return "無弱點"
        }
    }
    
    private var totalPackageCount: Int {
        viewModel.aiTools.count + viewModel.npmPackages.count + viewModel.pythonPackages.count + viewModel.brewPackages.count
    }
    
    private var severitySegments: [(value: Double, color: Color)] {
        func count(_ severities: [VulnerabilitySeverity]) -> Double {
            Double(viewModel.vulnerabilities.filter { severities.contains($0.severity) }.count)
        }
        return [
            (count([.critical]), DK.danger),
            (count([.high]), DK.warning),
            (count([.medium, .low, .unknown]), DK.textTertiary)
        ]
    }
    
    private var categories: some View {
        VStack(spacing: 0) {
            CategoryRow(source: .ai, title: NavigationTab.aiTools.title, outdated: viewModel.outdatedAIToolCount, total: viewModel.aiTools.count) { openTab(.aiTools) }
            CategoryRow(source: .npm, title: NavigationTab.npm.title, outdated: viewModel.outdatedNpmCount, total: viewModel.npmPackages.count) { openTab(.npm) }
            CategoryRow(source: .python, title: NavigationTab.python.title, outdated: viewModel.outdatedPythonCount, total: viewModel.pythonPackages.count) { openTab(.python) }
            CategoryRow(source: .homebrew, title: NavigationTab.brew.title, outdated: viewModel.outdatedBrewCount, total: viewModel.brewPackages.count) { openTab(.brew) }
        }
    }
    
    private func preview(_ items: [PreviewItem]) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.tight) {
            ForEach(items.prefix(4)) { item in
                HStack(spacing: DK.Space.s) {
                    Text(item.name)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: DK.Space.s)
                    Text("\(item.current) → \(item.latest)")
                        .font(DK.Font.mono)
                        .foregroundColor(DK.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)
                }
            }
            if items.count > 4 {
                Button {
                    openTab(.overview)
                } label: {
                    Text("還有 \(items.count - 4) 項，在主視窗查看")
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textTertiary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(DKPressStyle())
            }
        }
    }
    
    @ViewBuilder
    private var footer: some View {
        if confirmingUpgrade {
            VStack(alignment: .leading, spacing: DK.Space.s) {
                Text("將更新清單上 \(upgradableCount) 個 npm 與 Homebrew 項目，不會更新其他套件。")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: DK.Space.s) {
                    Spacer()
                    DKButton("取消") { confirmingUpgrade = false }
                    DKButton("確認更新", kind: .primary) {
                        confirmingUpgrade = false
                        Task {
                            await viewModel.upgradeAllOutdatedNpm()
                            await viewModel.upgradeAllOutdatedBrew()
                        }
                    }
                    .disabled(viewModel.isActionRunning || viewModel.isScanning || upgradableCount == 0)
                }
            }
            // The number shown must match what will run; ask again if it changes.
            .onChange(of: upgradableCount) { _, _ in confirmingUpgrade = false }
        } else {
            HStack(spacing: DK.Space.s) {
                if upgradableCount > 0 {
                    DKButton("更新 npm 與 Homebrew（\(upgradableCount)）") {
                        confirmingUpgrade = true
                    }
                    .disabled(viewModel.isActionRunning || viewModel.isScanning)
                }
                Spacer(minLength: 0)
                DKButton("設定", kind: .ghost) { openTab(.settings) }
                DKButton("結束", kind: .ghost) { NSApplication.shared.terminate(nil) }
                    .padding(.trailing, -DK.Space.m)
            }
        }
    }
    
    // MARK: - Navigation
    
    private func openMainWindow() {
        onClose()
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

private struct CategoryRow: View {
    let source: DKSource
    let title: String
    let outdated: Int
    let total: Int
    let action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: DK.Space.s) {
                DKSourceBadge(source, size: 26)
                VStack(alignment: .leading, spacing: DK.Space.xs) {
                    HStack {
                        Text(title)
                            .font(DK.Font.body)
                            .foregroundColor(DK.textPrimary)
                        Spacer()
                        Text(outdated > 0 ? "\(outdated) 可更新" : "最新")
                            .font(DK.Font.caption)
                            .monospacedDigit()
                            .foregroundColor(outdated > 0 ? DK.textPrimary : DK.textTertiary)
                    }
                    DKBar(value: total > 0 ? Double(outdated) / Double(total) : 0, height: 3)
                }
            }
            .padding(.horizontal, DK.Space.s)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous)
                    .fill(isHovering ? DK.surfaceHover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .onHover { isHovering = $0 }
    }
}

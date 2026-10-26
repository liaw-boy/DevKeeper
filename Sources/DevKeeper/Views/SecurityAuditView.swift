import DevKeeperCore
import SwiftUI
import AppKit

public struct SecurityAuditView: View {
    @ObservedObject var viewModel: AppViewModel
    
    @State private var filterSeverity: SeverityFilter = .all
    @State private var filterEcosystem: EcosystemFilter = .all
    @State private var searchKeyword: String = ""
    @State private var copiedFixCommandId: String? = nil
    @State private var locallyFixedGroupIds: Set<String> = []
    @Environment(\.dkOverlay) private var overlay
    
    enum SeverityFilter: String, CaseIterable, Identifiable {
        case all = "全部等級"
        case critical = "嚴重 (Critical)"
        case high = "高危 (High)"
        case medium = "中危 (Moderate)"
        case low = "低危 (Low)"
        
        var id: String { rawValue }
    }
    
    enum EcosystemFilter: String, CaseIterable, Identifiable {
        case all = "全部生態"
        case npm = "前端 / Node (npm)"
        case python = "後端 / Python (PyPI)"
        
        var id: String { rawValue }
    }
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredGroups: [PackageVulnerabilityGroup] {
        viewModel.groupedVulnerabilities.filter { group in
            if locallyFixedGroupIds.contains(group.id) { return false }
            
            // Severity filter
            switch filterSeverity {
            case .all: break
            case .critical: if group.highestSeverity != .critical { return false }
            case .high: if group.highestSeverity != .high { return false }
            case .medium: if group.highestSeverity != .medium { return false }
            case .low: if group.highestSeverity != .low { return false }
            }
            
            // Ecosystem filter
            switch filterEcosystem {
            case .all: break
            case .npm: if group.ecosystem.lowercased() != "npm" { return false }
            case .python: if group.ecosystem.lowercased() != "pypi" { return false }
            }
            
            // Search keyword
            if !searchKeyword.trimmingCharacters(in: .whitespaces).isEmpty {
                let q = searchKeyword.lowercased()
                let nameMatch = group.packageName.lowercased().contains(q)
                let cveMatch = group.cveList.contains { $0.lowercased().contains(q) }
                let descMatch = group.vulnerabilities.contains { $0.summary.lowercased().contains(q) }
                if !nameMatch && !cveMatch && !descMatch { return false }
            }
            
            return true
        }
    }
    
    private func remediationMessage(_ plan: RemediationPlan) -> String {
        var lines: [String] = []
        if plan.kind == .migrate {
            if !plan.toolsToInstall.isEmpty {
                lines.append("將用新版 Python 安裝到 uv 獨立環境：\(plan.toolsToInstall.joined(separator: "、"))")
            }
            if !plan.toolsAlreadyInUV.isEmpty {
                lines.append("已有獨立環境，不需重裝：\(plan.toolsAlreadyInUV.joined(separator: "、"))")
            }
        }
        lines.append("將從 \(plan.interpreterLabel) 移除 \(plan.packagesToRemove.count) 個套件：\(plan.packagesToRemove.joined(separator: "、"))")
        lines.append("注意：如果你自己的腳本在該 Python 裡 import 這些套件，移除後會無法執行。新工具的指令會放在 ~/.local/bin。")
        if plan.kind == .migrate {
            lines.append("所有新環境安裝成功後才會移除舊的；任何一步失敗都不會動舊環境。")
        }
        return lines.joined(separator: "\n\n")
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: DK.Space.m) {
                    filterBar
                    statusSection
                    fixProgress
                    groupList
                }
                .padding(.horizontal, DK.pagePadding)
                .padding(.bottom, DK.pagePadding)
            }
        }
        .background(DK.background)
        // A new audit replaces the list, so cards marked as fixed earlier must not stay hidden.
        .onChange(of: viewModel.isAuditingSecurity) { _, running in
            if !running { locallyFixedGroupIds = [] }
        }
        .onChange(of: viewModel.pendingBatch?.id) { _, id in
            guard id != nil, let batch = viewModel.pendingBatch else { return }
            // The panel owns the batch from here on, so a dismissed panel does not leave it pending.
            viewModel.pendingBatch = nil
            overlay?.present {
                RemediationBatchSheet(
                    batch: batch,
                    onConfirm: {
                        overlay?.dismissModal()
                        Task { await viewModel.runBatch(batch) }
                    },
                    onCancel: { overlay?.dismissModal() }
                )
            }
        }
    }
    
    // MARK: - Header and filters
    
    private var header: some View {
        DKPageHeader(
            "安全弱點",
            subtitle: "用 Google OSV 比對已安裝的 npm 與 Python 套件",
            count: viewModel.vulnerabilities.isEmpty
                ? nil
                : "\(viewModel.groupedVulnerabilities.count) 個套件、\(uniqueVulnerabilityCount) 個弱點"
        ) {
            DKActionMenu(help: "更多稽核選項", items: [
                .init(title: "稽核特定專案資料夾…", action: selectAndScanProjectFolder)
            ])
            DKButton("全面稽核", systemImage: "shield.lefthalf.filled", isLoading: viewModel.isAuditingSecurity) {
                Task { await viewModel.scanSecurityAudit() }
            }
            .disabled(viewModel.isAuditingSecurity)
            if !viewModel.vulnerabilities.isEmpty {
                DKButton("修復全部", systemImage: "wrench.and.screwdriver", kind: .primary,
                         isLoading: viewModel.isFixingAllVulnerabilities,
                         disabledReason: viewModel.isActionRunning ? "正在執行其他操作" : nil) {
                    let commands = viewModel.groupedVulnerabilities
                        .filter { !viewModel.isSystemBuiltIn($0) }
                        .flatMap(\.fixCommands)
                    overlay?.confirm(
                        "修復全部弱點？",
                        message: "將依序執行以下指令。修不了的套件會另外列出替代做法，確認後才會動作。",
                        commands: commands,
                        confirmTitle: "全部修復"
                    ) {
                        Task { await viewModel.fixAllVulnerabilities() }
                    }
                }
                .disabled(viewModel.isActionRunning)
            }
        }
    }
    
    private var filterBar: some View {
        HStack(spacing: DK.Space.s) {
            DKDropdown(options: SeverityFilter.allCases.map { ($0, $0.rawValue) }, selection: $filterSeverity)
            DKDropdown(options: EcosystemFilter.allCases.map { ($0, $0.rawValue) }, selection: $filterEcosystem)
            Spacer(minLength: DK.Space.s)
            DKSearchField(placeholder: "搜尋套件或 CVE 編號", text: $searchKeyword)
        }
    }
    
    // MARK: - Status
    
    /// Distinct advisories; the same CVE reported under several GHSA ids or environments counts once.
    private var uniqueVulnerabilityCount: Int {
        Set(viewModel.vulnerabilities.map { $0.cveId }).count
    }
    
    @ViewBuilder
    private var statusSection: some View {
        if viewModel.vulnerabilities.isEmpty {
            auditStatusBanner
        } else {
            if case .incomplete(let failed) = viewModel.auditState {
                banner(
                    symbol: "exclamationmark.triangle", tint: DK.warning,
                    title: "另有 \(failed) 個套件查詢失敗",
                    message: "下面的清單可能不完整。",
                    actionTitle: "重新稽核"
                ) { Task { await viewModel.scanSecurityAudit() } }
            }
        }
        ignoredNotice
    }
    
    @ViewBuilder
    private var auditStatusBanner: some View {
        switch viewModel.auditState {
        case .complete:
            banner(symbol: "checkmark.shield", tint: DK.success,
                   title: "沒有已知弱點",
                   message: "已用 Google OSV 比對完已安裝的 npm 與 Python 套件，沒有發現公開的弱點紀錄。")
        case .notRun:
            banner(symbol: "questionmark.circle", tint: DK.textSecondary,
                   title: viewModel.isAuditingSecurity ? "正在稽核…" : "尚未稽核",
                   message: "完成稽核前不會顯示「沒有弱點」。按「全面稽核」開始比對。")
        case .incomplete(let failed):
            banner(symbol: "exclamationmark.triangle", tint: DK.warning,
                   title: "稽核不完整：\(failed) 個套件查詢失敗",
                   message: "可能是網路中斷或查詢被限流，無法確認這些套件是否有弱點。請確認網路後重新稽核。",
                   actionTitle: "重新稽核") { Task { await viewModel.scanSecurityAudit() } }
        }
    }
    
    private func banner(symbol: String, tint: Color, title: String, message: String,
                        actionTitle: String? = nil, action: (() -> Void)? = nil) -> some View {
        HStack(spacing: DK.Space.m) {
            DKIconTile(symbol, size: 32, tint: tint)
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                Text(title)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                Text(message)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: DK.Space.m)
            if let actionTitle, let action {
                DKButton(actionTitle, action: action)
                    .disabled(viewModel.isAuditingSecurity)
            }
        }
        .dkCard()
    }
    
    /// Separate progress for any running fix, so the buttons themselves never change size or text.
    @ViewBuilder
    private var fixProgress: some View {
        if viewModel.isActionRunning && (viewModel.isFixingAllVulnerabilities || viewModel.fixingVulnId != nil) {
            VStack(alignment: .leading, spacing: DK.Space.s) {
                HStack {
                    Text(viewModel.actionStage.isEmpty ? "修復中…" : viewModel.actionStage)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: DK.Space.s)
                    Text("\(Int(min(max(viewModel.actionProgress, 0), 1) * 100))%")
                        .font(DK.Font.caption)
                        .monospacedDigit()
                        .foregroundColor(DK.textTertiary)
                }
                DKBar(value: min(max(viewModel.actionProgress, 0), 1))
            }
            .dkCard()
        }
    }
    
    @ViewBuilder
    private var ignoredNotice: some View {
        if viewModel.ignoredCount > 0 {
            HStack(spacing: DK.Space.s) {
                Image(systemName: "eye.slash")
                    .font(.system(size: DK.Icon.small))
                    .foregroundColor(DK.textTertiary)
                Text("已忽略 \(viewModel.ignoredCount) 個無法修復的已知風險（含系統內建 Python 附的 pip、setuptools、wheel）")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                Spacer(minLength: DK.Space.s)
                DKButton("全部還原", kind: .ghost) { Task { await viewModel.restoreIgnoredRisks() } }
            }
        }
    }
    
    // MARK: - List
    
    @ViewBuilder
    private var groupList: some View {
        if !filteredGroups.isEmpty {
            VStack(spacing: DK.Space.s) {
                ForEach(filteredGroups) { group in
                    groupCard(group)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        } else if !viewModel.vulnerabilities.isEmpty {
            DKEmptyState(kind: .empty, title: "沒有符合條件的弱點", message: "調整篩選條件或清除搜尋文字。")
                .dkCard(padding: 0)
        }
    }
    
    private func severityTone(_ severity: VulnerabilitySeverity) -> DKTag.Tone {
        switch severity {
        case .critical, .high: return .danger
        case .medium: return .warning
        case .low, .unknown: return .neutral
        }
    }
    
    private func osvLink(_ cve: String) -> some View {
        Button {
            if let url = VulnerabilityItem.osvUrl(for: cve) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(spacing: DK.Space.xxs) {
                Text(cve)
                    .font(DK.Font.mono)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: DK.Icon.tiny))
            }
            .foregroundColor(DK.accent)
        }
        .buttonStyle(DKPressStyle())
        .dkTooltip("在 Google OSV 查看 \(cve)")
    }
    
    private func groupCard(_ group: PackageVulnerabilityGroup) -> some View {
        let isFixing = viewModel.isActionRunning && viewModel.fixingVulnId == group.id
        let isCompleted = viewModel.completedPackageId == group.id
        let builtIn = viewModel.isSystemBuiltIn(group)
        
        return VStack(alignment: .leading, spacing: DK.Space.m) {
            HStack(spacing: DK.Space.s) {
                DKTag(group.highestSeverity.localizedName, tone: severityTone(group.highestSeverity))
                Text(group.packageName)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                DKTag(group.ecosystem.uppercased())
                ForEach(group.environments, id: \.pythonPath) { env in
                    DKTag(env.label)
                }
                Spacer(minLength: DK.Space.s)
                HStack(spacing: DK.Space.tight) {
                    Text(group.currentVersion)
                        .font(DK.Font.mono)
                        .foregroundColor(DK.danger)
                    if let safe = group.targetSafeVersion {
                        Image(systemName: "arrow.right")
                            .font(.system(size: DK.Icon.tiny, weight: .semibold))
                            .foregroundColor(DK.textTertiary)
                        Text(safe)
                            .font(DK.Font.mono)
                            .foregroundColor(DK.success)
                    }
                }
                .lineLimit(1)
                .fixedSize()
                cardAction(group, isFixing: isFixing, isCompleted: isCompleted, builtIn: builtIn)
            }
            
            if builtIn {
                Text("這是 Apple 內建的 Python，無法在這裡升級（修復版本需要 Python 3.10 以上）。實際用的程式請改用 Homebrew 或 uv 的 Python，或忽略這項風險。")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            HStack(spacing: DK.Space.m) {
                ForEach(group.cveList.prefix(3), id: \.self) { osvLink($0) }
                if group.cveList.count > 3 {
                    DKActionMenu(help: "其餘 \(group.cveList.count - 3) 個弱點", items: group.cveList.dropFirst(3).map { cve in
                        .init(title: "在 Google OSV 查看 \(cve)") {
                            if let url = VulnerabilityItem.osvUrl(for: cve) { NSWorkspace.shared.open(url) }
                        }
                    })
                }
                Spacer(minLength: 0)
            }
            
            VStack(alignment: .leading, spacing: DK.Space.xs) {
                ForEach(group.vulnerabilities.prefix(2)) { v in
                    HStack(alignment: .firstTextBaseline, spacing: DK.Space.s) {
                        Text(v.cveId)
                            .font(DK.Font.mono)
                            .foregroundColor(DK.textTertiary)
                        Text(v.summary)
                            .font(DK.Font.caption)
                            .foregroundColor(DK.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .dkTooltip(v.summary)
                    }
                }
                if group.vulnerabilities.count > 2 {
                    Text("還有 \(group.vulnerabilities.count - 2) 個相關弱點")
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textTertiary)
                }
            }
            
            ForEach(group.fixTargets) { target in
                targetStatus(group: group, target: target)
            }
            
            if !group.fixCommand.isEmpty, !builtIn {
                fixCommandButton(group)
            }
        }
        .dkCard()
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .stroke(isCompleted ? DK.success.opacity(0.6) : Color.clear, lineWidth: 1)
        )
    }
    
    @ViewBuilder
    private func cardAction(_ group: PackageVulnerabilityGroup, isFixing: Bool, isCompleted: Bool, builtIn: Bool) -> some View {
        if isCompleted {
            HStack(spacing: DK.Space.xs) {
                Image(systemName: "checkmark")
                    .font(.system(size: DK.Icon.small, weight: .semibold))
                Text("已修復")
                    .font(DK.Font.caption)
            }
            .foregroundColor(DK.success)
        } else if isFixing {
            HStack(spacing: DK.Space.s) {
                DKSpinner(size: 12)
                Text("修復中…")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
            }
        } else if builtIn {
            DKButton("忽略此風險") {
                for env in group.environments { viewModel.ignoreRisk(group: group, environment: env) }
            }
        } else {
            DKButton("修復", systemImage: "wrench.and.screwdriver", kind: .primary,
                     disabledReason: viewModel.isActionRunning ? "正在執行其他操作" : (group.fixCommand.isEmpty ? "沒有可自動執行的修復指令" : nil)) {
                let commands = group.fixCommands
                overlay?.confirm(
                    "修復 \(group.packageName)？",
                    message: "將執行以下指令，升級到沒有已知弱點的版本。",
                    commands: commands,
                    confirmTitle: "修復"
                ) {
                    Task {
                        if await viewModel.fixVulnerabilityGroup(group: group) {
                            _ = withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                locallyFixedGroupIds.insert(group.id)
                            }
                        }
                    }
                }
            }
            .disabled(viewModel.isActionRunning || group.fixCommand.isEmpty)
        }
    }
    
    private func fixCommandButton(_ group: PackageVulnerabilityGroup) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(group.fixCommands.joined(separator: "\n"), forType: .string)
            copiedFixCommandId = group.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if copiedFixCommandId == group.id { copiedFixCommandId = nil }
            }
        } label: {
            HStack(spacing: DK.Space.xs) {
                Text("$ \(group.fixCommand)")
                    .font(DK.Font.mono)
                    .foregroundColor(DK.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if group.fixCommands.count > 1 {
                    Text("+\(group.fixCommands.count - 1) 個環境")
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textTertiary)
                }
                Image(systemName: copiedFixCommandId == group.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: DK.Icon.tiny))
                    .foregroundColor(copiedFixCommandId == group.id ? DK.success : DK.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .dkTooltip(copiedFixCommandId == group.id ? "已複製" : "複製修復指令")
    }
    
    /// Version, failure reason and alternative fixes for one environment of a package.
    @ViewBuilder
    private func targetStatus(group: PackageVulnerabilityGroup, target: FixTarget) -> some View {
        let key = group.key(for: target.environment)
        let multi = group.fixTargets.count > 1
        let prefix = (multi ? target.environment?.label.appending("：") : nil) ?? ""
        if multi {
            HStack(spacing: DK.Space.tight) {
                Text(target.environment?.label ?? "全域")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                Text(target.currentVersion)
                    .font(DK.Font.mono)
                    .foregroundColor(DK.danger)
                if let safe = group.targetSafeVersion {
                    Image(systemName: "arrow.right")
                        .font(.system(size: DK.Icon.tiny, weight: .semibold))
                        .foregroundColor(DK.textTertiary)
                    Text(safe)
                        .font(DK.Font.mono)
                        .foregroundColor(DK.success)
                }
            }
        }
        
        if let failure = viewModel.fixFailures[key] {
            HStack(alignment: .top, spacing: DK.Space.s) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: DK.Icon.small))
                    .foregroundColor(DK.warning)
                Text(prefix + failure)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DK.Space.s)
                DKButton("忽略此風險") { viewModel.ignoreRisk(group: group, environment: target.environment) }
                    .dkTooltip("這個版本的 Python 裝不到修復版本。忽略後不再列入警告；升級該套件後會自動重新檢查。")
            }
            .padding(DK.Space.m)
            .background(RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous).fill(DK.surfaceSunken))
        }
        
        if let plan = viewModel.remediationPlans[key] {
            HStack(spacing: DK.Space.m) {
                Image(systemName: plan.kind == .migrate ? "arrow.triangle.branch" : "trash")
                    .font(.system(size: DK.Icon.regular))
                    .foregroundColor(DK.accent)
                VStack(alignment: .leading, spacing: DK.Space.xxs) {
                    Text(plan.kind == .migrate
                         ? "可改為：把 \((plan.toolsToInstall + plan.toolsAlreadyInUV).joined(separator: "、")) 放進 uv 獨立環境"
                         : "可改為：直接移除（沒有其他套件依賴它）")
                        .font(DK.Font.bodyMedium)
                        .foregroundColor(DK.textPrimary)
                    Text("會從 \(plan.interpreterLabel) 清除 \(plan.packagesToRemove.count) 個套件，確認前不會動作")
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                }
                Spacer(minLength: DK.Space.s)
                DKButton(plan.kind == .migrate ? "搬到獨立環境" : "移除套件", kind: plan.kind == .migrate ? .secondary : .danger) {
                    overlay?.confirm(
                        plan.kind == .migrate ? "把 \(plan.packageName) 所屬的工具搬到獨立環境？" : "移除 \(plan.packageName)？",
                        message: remediationMessage(plan),
                        confirmTitle: plan.kind == .migrate ? "確認搬移" : "確認移除",
                        destructive: true
                    ) {
                        Task { await viewModel.executeRemediation(plan, groupId: group.id, key: key) }
                    }
                }
                .disabled(viewModel.isActionRunning)
            }
            .padding(DK.Space.m)
            .background(RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous).fill(DK.surfaceSunken))
        } else if let note = viewModel.remediationNotes[key] {
            Text(prefix + note)
                .font(DK.Font.caption)
                .foregroundColor(DK.textSecondary)
        }
    }
    
    private func selectAndScanProjectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "選擇專案目錄掃描"
        
        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await viewModel.auditLocalProject(at: url)
            }
        }
    }
}

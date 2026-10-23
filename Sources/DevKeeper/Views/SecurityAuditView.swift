import SwiftUI
import AppKit

public struct SecurityAuditView: View {
    @ObservedObject var viewModel: AppViewModel
    
    @State private var filterSeverity: SeverityFilter = .all
    @State private var filterEcosystem: EcosystemFilter = .all
    @State private var searchKeyword: String = ""
    @State private var copiedFixCommandId: String? = nil
    @State private var locallyFixedGroupIds: Set<String> = []
    @State private var pendingRemediation: PendingRemediation? = nil
    
    struct PendingRemediation: Identifiable {
        let plan: RemediationPlan
        let groupId: String
        let key: String
        var id: String { key }
    }
    
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
    
    private var remediationDialogShown: Binding<Bool> {
        Binding(get: { pendingRemediation != nil }, set: { if !$0 { pendingRemediation = nil } })
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
        content
            .sheet(item: Binding(get: { viewModel.pendingBatch }, set: { viewModel.pendingBatch = $0 })) { batch in
                RemediationBatchSheet(
                    batch: batch,
                    onConfirm: { Task { await viewModel.runBatch(batch) } },
                    onCancel: { viewModel.pendingBatch = nil }
                )
            }
            .confirmationDialog(
                pendingRemediation.map { $0.plan.kind == .migrate ? "要把 \($0.plan.packageName) 所屬的工具搬到獨立環境嗎？" : "要移除 \($0.plan.packageName) 嗎？" } ?? "",
                isPresented: remediationDialogShown,
                titleVisibility: .visible,
                presenting: pendingRemediation
            ) { pending in
                Button(pending.plan.kind == .migrate ? "確認搬移" : "確認移除", role: .destructive) {
                    Task { await viewModel.executeRemediation(pending.plan, groupId: pending.groupId, key: pending.key) }
                }
                Button("取消", role: .cancel) {}
            } message: { pending in
                Text(remediationMessage(pending.plan))
            }
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Filter Bar
            filterBar
            
            Divider()
                .background(Theme.subtleBorder)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Security Health Banner
                    if viewModel.vulnerabilities.isEmpty {
                        cleanHealthBanner
                    } else {
                        vulnerabilitiesDetectedBanner
                        fixProgressBar
                    }
                    
                    // Vulnerability List (Consolidated One Card per Package)
                    if !filteredGroups.isEmpty {
                        VStack(spacing: 12) {
                            ForEach(filteredGroups) { group in
                                vulnerabilityGroupCard(group: group)
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
                    } else if !viewModel.vulnerabilities.isEmpty {
                        HStack {
                            Spacer()
                            Text("沒有符合當前篩選條件的弱點項目")
                                .font(.system(size: 12.5))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 30)
                            Spacer()
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.canvasBackground)
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(viewModel.vulnerabilities.isEmpty ? Theme.successGreen : Theme.dangerRed)
                    
                    Text("安全弱點稽核 (CVE / OSV)")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if !viewModel.vulnerabilities.isEmpty {
                        Text("\(viewModel.groupedVulnerabilities.count) 個套件受影響 (共 \(viewModel.vulnerabilities.count) 個 CVE)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Theme.dangerRed)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Theme.dangerRed.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                
                Text("深度比對 Google OSV 資料庫，全面掃描本機已安裝套件與前後端專案之安全漏洞")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                // Unified Full Security Audit Button
                Button(action: {
                    Task { await viewModel.scanSecurityAudit() }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isAuditingSecurity {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在全面稽核安全弱點...")
                                .font(.system(size: 12, weight: .semibold))
                        } else {
                            Image(systemName: "shield.lefthalf.filled")
                                .font(.system(size: 12, weight: .bold))
                            Text("全面安全弱點稽核")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 4, x: 0, y: 1.5)
                }
                .buttonStyle(.bouncy(scale: 0.97))
                .disabled(viewModel.isAuditingSecurity)
                
                // Advanced options: Custom folder audit
                Menu {
                    Button(action: {
                        selectAndScanProjectFolder()
                    }) {
                        Label("自選特定專案資料夾進行稽核...", systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help("自選特定資料夾進行稽核")
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
    
    // MARK: - Filter Bar
    private var filterBar: some View {
        HStack(spacing: 8) {
            // Severity Menu
            Menu {
                ForEach(SeverityFilter.allCases) { sev in
                    Button(action: { filterSeverity = sev }) {
                        if filterSeverity == sev {
                            Label(sev.rawValue, systemImage: "checkmark")
                        } else {
                            Text(sev.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 10.5))
                        .foregroundColor(filterSeverity != .all ? Theme.dangerRed : .secondary)
                    Text(filterSeverity.rawValue)
                        .font(.system(size: 11.5, weight: filterSeverity != .all ? .semibold : .medium))
                        .foregroundColor(filterSeverity != .all ? .white : .primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(filterSeverity != .all ? Theme.dangerRed.opacity(0.14) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(filterSeverity != .all ? Theme.dangerRed.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            // Ecosystem Menu
            Menu {
                ForEach(EcosystemFilter.allCases) { eco in
                    Button(action: { filterEcosystem = eco }) {
                        if filterEcosystem == eco {
                            Label(eco.rawValue, systemImage: "checkmark")
                        } else {
                            Text(eco.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cube")
                        .font(.system(size: 10.5))
                        .foregroundColor(filterEcosystem != .all ? Theme.primaryIndigo : .secondary)
                    Text(filterEcosystem.rawValue)
                        .font(.system(size: 11.5, weight: filterEcosystem != .all ? .semibold : .medium))
                        .foregroundColor(filterEcosystem != .all ? .white : .primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(filterEcosystem != .all ? Theme.primaryIndigo.opacity(0.14) : Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(filterEcosystem != .all ? Theme.primaryIndigo.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Search Bar (Unified 28pt height)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                TextField("搜尋套件或 CVE 編號...", text: $searchKeyword)
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
            .frame(width: 220, height: 28)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Theme.subtleBorder, lineWidth: 1)
            )
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }
    
    // MARK: - Banners
    private var cleanHealthBanner: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.successGreen.opacity(0.15))
                    .frame(width: 42, height: 42)
                Image(systemName: "shield.checkerboard")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.successGreen)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text("目前開發環境未偵測到已知安全性弱點")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                Text("已透過 Google OSV 國際資料庫驗證 npm 與 Python 套件清單，所有套件均無已知 CVE 漏洞。您亦可點擊上方按鈕掃描特定前後端網頁專案。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.successGreen.opacity(0.3), lineWidth: 1)
        )
    }
    
    /// Separate progress bar for any running fix, so the buttons themselves never change size or text.
    @ViewBuilder
    private var fixProgressBar: some View {
        if viewModel.isActionRunning && (viewModel.isFixingAllVulnerabilities || viewModel.fixingVulnId != nil) {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text(viewModel.actionStage.isEmpty ? "修復中..." : viewModel.actionStage)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text("\(Int(min(max(viewModel.actionProgress, 0), 1) * 100))%")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(Theme.primaryGradient)
                            .frame(width: geo.size.width * CGFloat(min(max(viewModel.actionProgress, 0.04), 1)))
                            .animation(.easeOut(duration: 0.3), value: viewModel.actionProgress)
                    }
                }
                .frame(height: 6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.subtleBorder, lineWidth: 1)
            )
        }
    }
    
    private var vulnerabilitiesDetectedBanner: some View {
        HStack(spacing: 14) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 26))
                .foregroundColor(Theme.dangerRed)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("偵測到 \(viewModel.groupedVulnerabilities.count) 個套件存在安全性弱點 (共 \(viewModel.vulnerabilities.count) 個 CVE 漏洞)")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Button(action: {
                        if let url = URL(string: "https://osv.dev") {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text("Google OSV 資料庫")
                                .font(.system(size: 10.5, weight: .medium))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7.5, weight: .bold))
                        }
                        .foregroundColor(Theme.primaryIndigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Theme.primaryIndigo.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("造訪 Google OSV (Open Source Vulnerabilities) 官方資料庫首頁")
                }
                
                Text("已為您整合最佳建議修復版本。點擊「🛠 一鍵修復」即可自動升級至安全版本；點擊 CVE 編號可直接開啟 Google OSV 官方漏洞報告。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                Task {
                    await viewModel.fixAllVulnerabilities()
                }
            }) {
                HStack(spacing: 6) {
                    if viewModel.isFixingAllVulnerabilities {
                        ProgressView().controlSize(.small)
                        Text("修復中")
                            .font(.system(size: 12, weight: .semibold))
                    } else {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 11))
                        Text("一鍵修復所有弱點")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .foregroundColor(.white)
                .frame(width: 150)
                .padding(.vertical, 7.5)
                .opacity(viewModel.isFixingAllVulnerabilities ? 0.75 : 1)
                .background(Theme.dangerRed)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .shadow(color: Theme.dangerRed.opacity(0.35), radius: 4, x: 0, y: 1.5)
            }
            .buttonStyle(.bouncy(scale: 0.97))
            .disabled(viewModel.isActionRunning)
        }
        .padding(16)
        .background(Theme.dangerRed.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.dangerRed.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Vulnerability Group Card (Integrated & Consolidated)
    /// Version, failure reason and alternative fixes for one environment of a package.
    @ViewBuilder
    private func targetStatus(group: PackageVulnerabilityGroup, target: FixTarget) -> some View {
        let key = group.key(for: target.environment)
        let multi = group.fixTargets.count > 1
        let prefix = (multi ? target.environment?.label.appending("：") : nil) ?? ""
        
        if multi {
            HStack(spacing: 6) {
                Text(target.environment?.label ?? "全域")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(Theme.infoCyan)
                Text(target.currentVersion)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Theme.dangerRed)
                if let safe = group.targetSafeVersion {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Theme.successGreen)
                    Text(safe)
                        .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.successGreen)
                }
            }
        }
        
        if let failure = viewModel.fixFailures[key] {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundColor(Theme.warningAmber)
                Text(prefix + failure)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Theme.warningAmber.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        
        if let plan = viewModel.remediationPlans[key] {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: plan.kind == .migrate ? "arrow.triangle.branch" : "trash")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.primaryIndigo)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.kind == .migrate
                         ? "可改為：把 \((plan.toolsToInstall + plan.toolsAlreadyInUV).joined(separator: "、")) 放進 uv 獨立環境"
                         : "可改為：直接移除（沒有其他套件依賴它）")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("會從 \(plan.interpreterLabel) 清除 \(plan.packagesToRemove.count) 個套件，確認前不會動作")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
                Button(action: {
                    pendingRemediation = PendingRemediation(plan: plan, groupId: group.id, key: key)
                }) {
                    Text(plan.kind == .migrate ? "搬到獨立環境" : "移除套件")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 5)
                        .background(Theme.primaryIndigo)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.bouncy)
                .disabled(viewModel.isActionRunning)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Theme.primaryIndigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.primaryIndigo.opacity(0.3), lineWidth: 1)
            )
        } else if let note = viewModel.remediationNotes[key] {
            Text(prefix + note)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }
    
    private func vulnerabilityGroupCard(group: PackageVulnerabilityGroup) -> some View {
        let isFixing = viewModel.isActionRunning && viewModel.fixingVulnId == group.id
        let isCompleted = viewModel.completedPackageId == group.id
        
        return VStack(alignment: .leading, spacing: 8) {
            // Tier 1: Identity (Left) vs Primary Fix Action Button (Right)
            HStack(alignment: .center, spacing: 8) {
                // Severity Badge
                Text(group.highestSeverity.localizedName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(severityColor(group.highestSeverity))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(severityColor(group.highestSeverity).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                // Package name
                Text(group.packageName)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundColor(.primary)
                
                // Ecosystem tag
                Text(group.ecosystem.uppercased())
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                
                ForEach(group.environments, id: \.pythonPath) { env in
                    Text(env.label)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Theme.infoCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Theme.infoCyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
                
                Spacer()
                
                // Primary Action Button (Fixed position at Top-Right of Card)
                if isFixing || isCompleted {
                    HStack(spacing: 5) {
                        if isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10.5))
                            Text("修復完成")
                                .font(.system(size: 11.5, weight: .semibold))
                        } else {
                            ProgressView().controlSize(.small)
                            Text("修復中")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                    }
                    .foregroundColor(isCompleted ? Theme.successGreen : .white)
                    .frame(width: 84)
                    .padding(.vertical, 5)
                    .background(isCompleted ? Theme.successGreen.opacity(0.15) : Theme.primaryIndigo.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Button(action: {
                        Task {
                            if await viewModel.fixVulnerabilityGroup(group: group) {
                                _ = withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                                    locallyFixedGroupIds.insert(group.id)
                                }
                            }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "wrench.and.screwdriver.fill")
                                .font(.system(size: 10.5))
                            Text("一鍵修復")
                                .font(.system(size: 11.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 84)
                        .padding(.vertical, 5)
                        .background(Theme.primaryIndigo)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 3, x: 0, y: 1)
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isActionRunning || group.fixCommand.isEmpty)
                }
            }
            
            // Tier 2: Security CVE Chips (Left) vs Version Transition Pill (Right - Never wraps!)
            HStack(alignment: .center, spacing: 8) {
                // CVE tags (Clickable links to Google OSV database)
                ForEach(group.cveList.prefix(3), id: \.self) { cve in
                    Button(action: {
                        if let url = VulnerabilityItem.osvUrl(for: cve) {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        HStack(spacing: 3) {
                            Text(cve)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundColor(Theme.infoCyan)
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Theme.infoCyan.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .help("點擊在 Google OSV 安全資料庫中查看 \(cve) 詳細漏洞說明")
                }
                if group.cveList.count > 3 {
                    Menu {
                        ForEach(group.cveList.dropFirst(3), id: \.self) { cve in
                            Button("在 Google OSV 查看 \(cve)") {
                                if let url = VulnerabilityItem.osvUrl(for: cve) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text("+\(group.cveList.count - 3)")
                                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6.5, weight: .bold))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                
                Spacer()
                
                // Version Transition: Current -> Target Safe Version (Never wraps into 2 lines!)
                HStack(spacing: 5) {
                    Text(group.currentVersion)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Theme.dangerRed)
                        .lineLimit(1)
                    
                    if let safe = group.targetSafeVersion {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Theme.successGreen)
                        
                        Text(safe)
                            .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(Theme.successGreen)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                .fixedSize()
            }
            
            // Tier 3: CVE summaries (with clickable OSV links)
            VStack(alignment: .leading, spacing: 3) {
                ForEach(group.vulnerabilities.prefix(2)) { v in
                    HStack(alignment: .top, spacing: 5) {
                        Button(action: {
                            if let url = v.osvUrl {
                                NSWorkspace.shared.open(url)
                            }
                        }) {
                            HStack(spacing: 2) {
                                Text("• [\(v.cveId)]")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 7, weight: .bold))
                            }
                            .foregroundColor(Theme.infoCyan)
                        }
                        .buttonStyle(.plain)
                        .help("在 Google OSV 查看 \(v.cveId) 弱點報告")
                        
                        Text(v.summary)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                if group.vulnerabilities.count > 2 {
                    Text("... 以及其他 \(group.vulnerabilities.count - 2) 個關聯漏洞")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            ForEach(group.fixTargets) { target in
                targetStatus(group: group, target: target)
            }
            
            // Tier 4: Interactive Repair Command Chip with 1-click copy
            if !group.fixCommand.isEmpty {
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(group.fixCommands.joined(separator: "\n"), forType: .string)
                copiedFixCommandId = group.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    if copiedFixCommandId == group.id { copiedFixCommandId = nil }
                }
            }) {
                HStack(spacing: 5) {
                    Text("$")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.primaryIndigo)
                    Text(group.fixCommand)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    if group.fixCommands.count > 1 {
                        Text("+\(group.fixCommands.count - 1) 個環境")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary.opacity(0.8))
                    }
                    
                    Image(systemName: copiedFixCommandId == group.id ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(copiedFixCommandId == group.id ? Theme.successGreen : Theme.primaryIndigo)
                    
                    if copiedFixCommandId == group.id {
                        Text("已複製修復指令")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(Theme.successGreen)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(copiedFixCommandId == group.id ? Theme.successGreen.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .help("點擊複製終端機修復指令：\(group.fixCommand)")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isCompleted ? Theme.successGreen.opacity(0.12) : Theme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isCompleted ? Theme.successGreen.opacity(0.6) : Theme.subtleBorder, lineWidth: isCompleted ? 1.5 : 1)
        )
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
    
    private func severityColor(_ severity: VulnerabilitySeverity) -> Color {
        switch severity {
        case .critical: return Theme.dangerRed
        case .high: return Color(red: 0.95, green: 0.4, blue: 0.2)
        case .medium: return Theme.warningAmber
        case .low: return Theme.infoCyan
        case .unknown: return Color.secondary
        }
    }
}

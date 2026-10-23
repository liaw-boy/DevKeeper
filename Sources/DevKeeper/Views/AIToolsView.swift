import SwiftUI

public struct AIToolsView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var filterMode: FilterMode = .all
    @State private var copiedCommand: String? = nil
    @State private var pendingScriptTool: AIToolItem? = nil
    @State private var pendingScriptIsInstall = true
    
    enum FilterMode: String, CaseIterable, Identifiable {
        case all = "全部工具"
        case installed = "已安裝"
        case outdated = "有新版本"
        
        var id: String { rawValue }
    }
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredTools: [AIToolItem] {
        switch filterMode {
        case .all:
            return viewModel.aiTools
        case .installed:
            return viewModel.aiTools.filter { $0.isInstalled }
        case .outdated:
            return viewModel.aiTools.filter { $0.isOutdated }
        }
    }
    
    private var remoteScriptDialogShown: Binding<Bool> {
        Binding(
            get: { pendingScriptTool != nil },
            set: { if !$0 { pendingScriptTool = nil } }
        )
    }
    
    public var body: some View {
        content
            .confirmationDialog(
                "要執行遠端下載的腳本嗎？",
                isPresented: remoteScriptDialogShown,
                titleVisibility: .visible,
                presenting: pendingScriptTool
            ) { tool in
                Button("確認並執行", role: .destructive) {
                    let isInstall = pendingScriptIsInstall
                    Task {
                        if isInstall {
                            await viewModel.installAITool(item: tool, confirmedRemoteScript: true)
                        } else {
                            await viewModel.upgradeAITool(item: tool, confirmedRemoteScript: true)
                        }
                    }
                }
                Button("取消", role: .cancel) {}
            } message: { tool in
                Text("\(tool.name) 的\(pendingScriptIsInstall ? "安裝" : "升級")指令會下載腳本並直接交給 shell 執行：\n\n\(pendingScriptIsInstall ? tool.installCommand : tool.updateCommand)\n\n請確認你信任該來源。")
            }
    }
    
    private var content: some View {
        VStack(spacing: 0) {
            // Header Bar
            headerView
            
            Divider()
                .background(Theme.subtleBorder)
            
            ScrollView {
                VStack(spacing: 20) {
                    // Summary Stat Cards
                    summaryCards
                    
                    // Filter Picker
                    filterBar
                    
                    // Live Terminal Output if updating
                    if viewModel.isActionRunning && !viewModel.liveLogOutput.isEmpty {
                        liveTerminalCard
                    }
                    
                    // Tool Cards List
                    VStack(spacing: 12) {
                        ForEach(filteredTools) { tool in
                            aiToolCard(tool: tool)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
        .background(Theme.canvasBackground)
    }
    
    // MARK: - Header
    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.primaryIndigo)
                    Text("AI 開發工具版本管理")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                }
                Text("管理 Claude Code、AGY、OpenAI Codex 等次世代 AI 終端協作工具")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Refresh Button
            Button(action: {
                Task {
                    await viewModel.scanAITools()
                }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5, weight: .semibold))
                        .rotationEffect(.degrees(viewModel.isScanning ? 360 : 0))
                        .animation(viewModel.isScanning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: viewModel.isScanning)
                    Text("重新檢查")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7.5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.bouncy(scale: 0.97))
            .disabled(viewModel.isScanning || viewModel.isActionRunning)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
    
    // MARK: - Summary Cards
    private var summaryCards: some View {
        let installedCount = viewModel.aiTools.filter { $0.isInstalled }.count
        let outdatedCount = viewModel.outdatedAIToolCount
        let totalCount = viewModel.aiTools.count
        
        return HStack(spacing: 14) {
            statMetricCard(
                title: "已就緒工具",
                value: "\(installedCount)",
                subtitle: "本機環境已偵測並可直接執行",
                symbol: "checkmark.circle.fill",
                accentColor: Theme.successGreen
            )
            
            statMetricCard(
                title: "待更新項目",
                value: "\(outdatedCount)",
                subtitle: outdatedCount > 0 ? "有新版本可一鍵更新升級" : "所有已安裝工具皆為最新版",
                symbol: outdatedCount > 0 ? "arrow.up.circle.fill" : "sparkles",
                accentColor: outdatedCount > 0 ? Theme.warningAmber : Theme.primaryIndigo
            )
            
            statMetricCard(
                title: "支援追蹤項目",
                value: "\(totalCount)",
                subtitle: "涵蓋 Claude Code, AGY, Aider 等",
                symbol: "wand.and.stars",
                accentColor: Color.blue
            )
        }
    }
    
    private func statMetricCard(title: String, value: String, subtitle: String, symbol: String, accentColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 14))
                    .foregroundColor(accentColor)
            }
            
            Text(value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.8))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
        )
    }
    
    // MARK: - Filter Bar
    private var filterBar: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(FilterMode.allCases) { mode in
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.15)) {
                            filterMode = mode
                        }
                    }) {
                        Text(mode.rawValue)
                            .font(.system(size: 12, weight: filterMode == mode ? .semibold : .medium))
                            .foregroundColor(filterMode == mode ? .white : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(filterMode == mode ? Color.white.opacity(0.12) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
            
            Spacer()
            
            if let cmd = copiedCommand {
                Text("已複製: \(cmd)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.successGreen)
                    .transition(.opacity)
            }
        }
    }
    
    // MARK: - Live Terminal Card
    private var liveTerminalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(Theme.warningAmber).frame(width: 7, height: 7)
                Text("指令執行輸出...")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                Spacer()
                ProgressView().controlSize(.small)
            }
            
            ScrollView {
                Text(viewModel.liveLogOutput)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 140)
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Theme.primaryIndigo.opacity(0.4), lineWidth: 1)
                )
        )
    }
    
    // MARK: - AI Tool Card
    private func aiToolCard(tool: AIToolItem) -> some View {
        let isRunningThis = viewModel.isActionRunning && viewModel.currentActionPackageId == tool.id
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                // Tool Icon Box
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tool.isInstalled ? Theme.primaryIndigo.opacity(0.12) : Color.white.opacity(0.04))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(tool.isInstalled ? Theme.primaryIndigo.opacity(0.3) : Theme.subtleBorder, lineWidth: 1)
                        )
                    
                    Image(systemName: tool.iconSymbol)
                        .font(.system(size: 19, weight: .medium))
                        .foregroundColor(tool.isInstalled ? Theme.primaryIndigo : .secondary)
                }
                
                // Info block
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(tool.name)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.primary)
                        
                        // Vendor tag
                        Text(tool.vendor)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                        
                        // Command tag
                        Text(tool.command)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(tool.isInstalled ? Theme.successGreen : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background((tool.isInstalled ? Theme.successGreen : Color.secondary).opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        
                        Spacer()
                        
                        // Status pill
                        if tool.isInstalled {
                            if tool.isOutdated {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.warningAmber).frame(width: 6, height: 6)
                                    Text("可升級至 v\(tool.latestVersion ?? "")")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Theme.warningAmber)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Theme.warningAmber.opacity(0.12))
                                .clipShape(Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.successGreen).frame(width: 6, height: 6)
                                    Text("最新版本")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Theme.successGreen)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Theme.successGreen.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        } else {
                            Text("未安裝")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3.5)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Capsule())
                        }
                    }
                    
                    Text(tool.summary)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    
                    // Interactive Update / Install Command Chip
                    let activeCmd = tool.isInstalled ? tool.updateCommand : tool.installCommand
                    if !activeCmd.isEmpty {
                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(activeCmd, forType: .string)
                            withAnimation {
                                copiedCommand = activeCmd
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                                withAnimation {
                                    if copiedCommand == activeCmd { copiedCommand = nil }
                                }
                            }
                        }) {
                            HStack(spacing: 5) {
                                Text("$")
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.primaryIndigo)
                                Text(activeCmd)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                
                                Image(systemName: copiedCommand == activeCmd ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 9.5))
                                    .foregroundColor(copiedCommand == activeCmd ? Theme.successGreen : Theme.primaryIndigo)
                                
                                if copiedCommand == activeCmd {
                                    Text("已複製")
                                        .font(.system(size: 9.5, weight: .semibold))
                                        .foregroundColor(Theme.successGreen)
                                }
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(copiedCommand == activeCmd ? Theme.successGreen.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .help("點擊複製\(tool.isInstalled ? "更新" : "安裝")指令：\(activeCmd)")
                    }
                }
            }
            
            Divider().background(Color.white.opacity(0.04))
            
            // Bottom Meta Row & Action Buttons
            HStack(alignment: .center) {
                // Version details
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("目前版本")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary.opacity(0.8))
                        Text(tool.isInstalled ? tool.currentVersion : "未安裝")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(tool.isInstalled ? .primary : .secondary)
                    }
                    
                    if let latest = tool.latestVersion {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("最新版本")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                            Text(latest)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundColor(tool.isOutdated ? Theme.warningAmber : .secondary)
                        }
                    }
                    
                    if let path = tool.binaryPath {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("安裝路徑")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary.opacity(0.8))
                            Text(path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 8) {
                    // Open website / docs
                    if let url = URL(string: tool.websiteUrl), !tool.websiteUrl.isEmpty {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            Image(systemName: "globe")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .help("開啟官方網站或說明文件")
                    }
                    
                    // Upgrade / Install Button
                    if tool.isInstalled {
                        Button(action: {
                            if tool.updateRunsRemoteScript {
                                pendingScriptIsInstall = false
                                pendingScriptTool = tool
                            } else {
                                Task { await viewModel.upgradeAITool(item: tool) }
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isRunningThis {
                                    ProgressView().controlSize(.small)
                                    Text("升級中...")
                                } else {
                                    Image(systemName: tool.isOutdated ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text(tool.isOutdated ? "一鍵升級" : "檢查更新")
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(tool.isOutdated ? .white : .primary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(tool.isOutdated ? Theme.primaryIndigo : Color.white.opacity(0.08))
                            )
                        }
                        .buttonStyle(.bouncy(scale: 0.97))
                        .disabled(viewModel.isActionRunning)
                    } else {
                        Button(action: {
                            if tool.installRunsRemoteScript {
                                pendingScriptIsInstall = true
                                pendingScriptTool = tool
                            } else {
                                Task { await viewModel.installAITool(item: tool) }
                            }
                        }) {
                            HStack(spacing: 6) {
                                if isRunningThis {
                                    ProgressView().controlSize(.small)
                                    Text("安裝中...")
                                } else {
                                    Image(systemName: "plus.circle")
                                        .font(.system(size: 11.5, weight: .semibold))
                                    Text("一鍵安裝")
                                }
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Theme.primaryIndigo)
                            )
                        }
                        .buttonStyle(.bouncy(scale: 0.97))
                        .disabled(viewModel.isActionRunning)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tool.isOutdated ? Theme.warningAmber.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                )
        )
    }
}

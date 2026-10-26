import DevKeeperCore
import SwiftUI

public struct AIToolsView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay
    @State private var filterMode: FilterMode = .all
    @State private var copiedCommand: String?
    
    enum FilterMode: Hashable { case all, installed, outdated }
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var installedCount: Int { viewModel.aiTools.filter(\.isInstalled).count }
    
    private var filteredTools: [AIToolItem] {
        switch filterMode {
        case .all:
            // Installed tools first; each group keeps its original order.
            return viewModel.aiTools.filter(\.isInstalled) + viewModel.aiTools.filter { !$0.isInstalled }
        case .installed:
            return viewModel.aiTools.filter(\.isInstalled)
        case .outdated:
            return viewModel.aiTools.filter(\.isOutdated)
        }
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DKPageHeader(
                    "AI 工具",
                    subtitle: "Claude Code、Codex、OpenCode 等命令列工具的版本",
                    count: viewModel.outdatedAIToolCount > 0 ? "\(viewModel.outdatedAIToolCount) 項可升級" : "已安裝 \(installedCount) 個"
                ) {
                    DKButton("重新檢查", systemImage: "arrow.clockwise", isLoading: viewModel.isScanning) {
                        Task { await viewModel.scanAITools() }
                    }
                    .disabled(viewModel.isScanning || viewModel.isActionRunning)
                }
                
                VStack(alignment: .leading, spacing: DK.Space.m) {
                    DKSegmented(options: [
                        (FilterMode.all, "全部 \(viewModel.aiTools.count)"),
                        (.installed, "已安裝 \(installedCount)"),
                        (.outdated, "可升級 \(viewModel.outdatedAIToolCount)")
                    ], selection: $filterMode)
                    
                    if viewModel.isActionRunning && !viewModel.liveLogOutput.isEmpty {
                        liveOutput
                    }
                    
                    if filteredTools.isEmpty {
                        DKEmptyState(
                            kind: filterMode == .outdated ? .allCurrent : .empty,
                            title: filterMode == .outdated ? "全部都是最新版本" : "沒有符合的工具"
                        )
                        .dkCard(padding: 0)
                    } else {
                        VStack(spacing: DK.Space.s) {
                            ForEach(filteredTools) { tool in
                                toolRow(tool)
                            }
                        }
                    }
                }
                .padding(.horizontal, DK.pagePadding)
                .padding(.bottom, DK.pagePadding)
            }
        }
        .background(DK.background)
    }
    
    // MARK: - Live output
    
    private var liveOutput: some View {
        VStack(alignment: .leading, spacing: DK.Space.s) {
            HStack(spacing: DK.Space.s) {
                DKSpinner(size: 12)
                Text("執行輸出")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
            }
            ScrollView {
                Text(viewModel.liveLogOutput)
                    .font(DK.Font.mono)
                    .foregroundColor(DK.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
        }
        .dkCard()
    }
    
    // MARK: - Row
    
    private func toolRow(_ tool: AIToolItem) -> some View {
        let isRunningThis = viewModel.isActionRunning && viewModel.currentActionPackageId == tool.id
        let busyElsewhere = viewModel.isActionRunning && !isRunningThis
        let command = tool.isInstalled ? tool.updateCommand : tool.installCommand
        
        return HStack(alignment: .center, spacing: DK.Space.m) {
            DKSourceBadge(.ai, size: 32)
                .opacity(tool.isInstalled ? 1 : 0.5)
            
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                HStack(spacing: DK.Space.s) {
                    Text(tool.name)
                        .font(DK.Font.bodyMedium)
                        .foregroundColor(DK.textPrimary)
                    DKTag(tool.vendor)
                }
                Text(tool.summary)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .dkTooltip(tool.summary)
                if !command.isEmpty, !tool.isInstalled || tool.isOutdated {
                    commandButton(command)
                }
            }
            .frame(minWidth: 200, alignment: .leading)
            
            Spacer(minLength: DK.Space.l)
            
            versions(tool)
                .frame(width: 170, alignment: .trailing)
            
            HStack(spacing: DK.Space.s) {
                if let url = InputValidator.httpsURL(tool.websiteUrl) {
                    DKIconButton("safari", help: "開啟官方網站", compact: true) { NSWorkspace.shared.open(url) }
                }
                action(tool, isRunningThis: isRunningThis, busyElsewhere: busyElsewhere)
            }
            .frame(width: 150, alignment: .trailing)
        }
        .padding(.vertical, DK.Space.s)
        .padding(.horizontal, DK.Space.m)
        .dkCard(padding: 0)
    }
    
    private func versions(_ tool: AIToolItem) -> some View {
        VStack(alignment: .trailing, spacing: DK.Space.xxs) {
            if tool.isInstalled {
                HStack(spacing: DK.Space.tight) {
                    Text(tool.currentVersion)
                        .font(DK.Font.mono)
                        .foregroundColor(DK.textSecondary)
                    if tool.isOutdated, let latest = tool.latestVersion {
                        Image(systemName: "arrow.right")
                            .font(.system(size: DK.Icon.tiny, weight: .semibold))
                            .foregroundColor(DK.accent)
                        Text(latest)
                            .font(DK.Font.mono)
                            .foregroundColor(DK.textPrimary)
                    }
                }
                .lineLimit(1)
                Text(tool.isOutdated ? "可升級" : "最新版本")
                    .font(DK.Font.caption)
                    .foregroundColor(tool.isOutdated ? DK.textPrimary : DK.textTertiary)
            } else {
                Text("未安裝")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textTertiary)
            }
        }
    }
    
    @ViewBuilder
    private func action(_ tool: AIToolItem, isRunningThis: Bool, busyElsewhere: Bool) -> some View {
        if isRunningThis {
            HStack(spacing: DK.Space.s) {
                DKSpinner(size: 12)
                Text(tool.isInstalled ? "升級中…" : "安裝中…")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
            }
        } else if !tool.isInstalled {
            DKButton("安裝", systemImage: "plus", disabledReason: busyElsewhere ? "正在執行其他操作" : nil) {
                confirm(tool, install: true)
            }
            .disabled(viewModel.isActionRunning)
        } else if tool.isOutdated {
            DKButton("升級", kind: .primary, disabledReason: busyElsewhere ? "正在執行其他操作" : nil) {
                confirm(tool, install: false)
            }
            .disabled(viewModel.isActionRunning)
        }
    }
    
    private func commandButton(_ command: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
            copiedCommand = command
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if copiedCommand == command { copiedCommand = nil }
            }
        } label: {
            HStack(spacing: DK.Space.xs) {
                Text("$ \(command)")
                    .font(DK.Font.mono)
                    .foregroundColor(DK.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copiedCommand == command ? "checkmark" : "doc.on.doc")
                    .font(.system(size: DK.Icon.tiny))
                    .foregroundColor(copiedCommand == command ? DK.success : DK.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .dkTooltip(copiedCommand == command ? "已複製" : "複製指令")
    }
    
    /// Always lists the exact command first; tools whose command pipes a download into a shell say so.
    private func confirm(_ tool: AIToolItem, install: Bool) {
        let command = install ? tool.installCommand : tool.updateCommand
        let remote = install ? tool.installRunsRemoteScript : tool.updateRunsRemoteScript
        let message = remote
            ? "這個指令會下載腳本並直接交給 shell 執行，請確認你信任該來源。"
            : "將執行以下指令。"
        overlay?.confirm(
            "\(install ? "安裝" : "升級") \(tool.name)？",
            message: message,
            commands: [command],
            confirmTitle: remote ? "確認並執行" : (install ? "安裝" : "升級"),
            destructive: remote
        ) {
            Task {
                if install {
                    await viewModel.installAITool(item: tool, confirmedRemoteScript: true)
                } else {
                    await viewModel.upgradeAITool(item: tool, confirmedRemoteScript: true)
                }
            }
        }
    }
}

import SwiftUI
import AppKit

public struct GitHubToolsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    @State private var filterKind: FilterOption = .all
    @State private var showAddSheet: Bool = false
    @State private var copiedCommandToolId: String? = nil
    
    // Add Sheet Form States
    @State private var newKind: GitHubToolKind = .appBundle
    @State private var inputRepo: String = ""
    @State private var inputName: String = ""
    @State private var selectedAppPath: String = ""
    @State private var isSubmitting: Bool = false
    @State private var errorMessage: String? = nil
    
    enum FilterOption: String, CaseIterable, Identifiable {
        case all = "全部"
        case apps = "桌面應用 (.app)"
        case cli = "CLI 工具"
        case outdated = "有新版本"
        
        var id: String { rawValue }
    }
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredTools: [GitHubToolItem] {
        switch filterKind {
        case .all:
            return viewModel.githubTools
        case .apps:
            return viewModel.githubTools.filter { $0.kind == .appBundle }
        case .cli:
            return viewModel.githubTools.filter { $0.kind == .cli }
        case .outdated:
            return viewModel.githubTools.filter { $0.isOutdated }
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            headerBar
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Sub-header / Filter & Actions
            filterAndActionBar
            
            Divider()
                .background(Theme.subtleBorder)
            
            // List of tracked tools
            ScrollView {
                VStack(spacing: 12) {
                    if filteredTools.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(filteredTools) { tool in
                            gitHubItemCard(tool: tool)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
        .background(Theme.canvasBackground)
        .sheet(isPresented: $showAddSheet) {
            addToolSheet
        }
    }
    
    // MARK: - Header Bar
    private var headerBar: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    GitHubMarkShape()
                        .fill(Theme.primaryIndigo)
                        .frame(width: 20, height: 20)
                    
                    Text("GitHub Releases 軟體與工具追蹤")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("\(viewModel.githubTools.count) 個項目")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                
                Text("追蹤 GitHub Releases 上的 macOS 桌面應用程式 (.app) 與二進位 CLI 工具")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            HStack(spacing: 10) {
                // Auto discover /Applications
                Button(action: {
                    Task {
                        await viewModel.autoDiscoverInstalledApps()
                        await viewModel.scanGitHubTools()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(Theme.primaryIndigo)
                        Text("自動掃描 /Applications")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.primaryIndigo.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.bouncy(scale: 0.97))
                .disabled(viewModel.isScanning)
                
                // Add Item Button
                Button(action: {
                    inputRepo = ""
                    inputName = ""
                    selectedAppPath = ""
                    errorMessage = nil
                    showAddSheet = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11.5, weight: .semibold))
                        Text("新增追蹤")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Theme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 4, x: 0, y: 1.5)
                }
                .buttonStyle(.bouncy(scale: 0.97))
                
                // Refresh Releases Button with Dynamic Visual Feedback
                Button(action: {
                    Task { await viewModel.scanGitHubTools() }
                }) {
                    HStack(spacing: 6) {
                        if viewModel.isCheckingGitHubReleases {
                            ProgressView()
                                .controlSize(.small)
                            Text("正在檢查 Releases...")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.primaryIndigo)
                        } else if let successMsg = viewModel.gitHubCheckSuccessMessage {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 11.5))
                                .foregroundColor(Theme.successGreen)
                            Text(successMsg)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.successGreen)
                        } else {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11.5, weight: .semibold))
                            Text("檢查更新")
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(viewModel.gitHubCheckSuccessMessage != nil ? Theme.successGreen.opacity(0.12) : Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(viewModel.gitHubCheckSuccessMessage != nil ? Theme.successGreen.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.bouncy(scale: 0.97))
                .disabled(viewModel.isCheckingGitHubReleases)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
    
    // MARK: - Filter Bar
    private var filterAndActionBar: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(FilterOption.allCases) { opt in
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.12)) {
                            filterKind = opt
                        }
                    }) {
                        Text(opt.rawValue)
                            .font(.system(size: 12, weight: filterKind == opt ? .semibold : .medium))
                            .foregroundColor(filterKind == opt ? .white : .secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 5.5)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(filterKind == opt ? Color.white.opacity(0.12) : Color.clear)
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
            
            if viewModel.outdatedGitHubCount > 0 {
                HStack(spacing: 4) {
                    Circle().fill(Theme.warningAmber).frame(width: 6, height: 6)
                    Text("\(viewModel.outdatedGitHubCount) 個項目有新 Release")
                        .font(.system(size: 11.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundColor(Theme.warningAmber)
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Theme.warningAmber.opacity(0.1))
                .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }
    
    // MARK: - Card View for each GitHub tool / app
    private func gitHubItemCard(tool: GitHubToolItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            // 1. App Icon
            Group {
                if tool.kind == .appBundle, let appPath = tool.appPath, FileManager.default.fileExists(atPath: appPath) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: appPath))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 38, height: 38)
                } else if tool.kind == .appBundle {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "macwindow")
                            .font(.system(size: 18))
                            .foregroundColor(Color.blue)
                    }
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.primaryIndigo.opacity(0.12))
                            .frame(width: 38, height: 38)
                        GitHubMarkShape()
                            .fill(Theme.primaryIndigo)
                            .frame(width: 19, height: 19)
                    }
                }
            }
            .fixedSize()
            
            // 2. Info Block (App Name, Type Badge, Repo & Path)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(tool.binaryName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(tool.kind == .appBundle ? "macOS App" : "CLI")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(tool.kind == .appBundle ? Color.blue : Theme.infoCyan)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background((tool.kind == .appBundle ? Color.blue : Theme.infoCyan).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    
                    Text("\(tool.owner)/\(tool.repo)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 6) {
                    if let path = tool.kind == .appBundle ? tool.appPath : tool.binaryPath {
                        Text(path)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(1)
                    }
                    if let asset = tool.assetName {
                        Text("• " + asset)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.6))
                            .lineLimit(1)
                    }
                }
                
                // If outdated, show CLI upgrade command chip with 1-click copy built-in
                if tool.isOutdated {
                    Button(action: {
                        let cmd = cliUpgradeCommand(for: tool)
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cmd, forType: .string)
                        copiedCommandToolId = tool.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            if copiedCommandToolId == tool.id { copiedCommandToolId = nil }
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text("$")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.primaryIndigo)
                            Text(cliUpgradeCommand(for: tool))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Image(systemName: copiedCommandToolId == tool.id ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundColor(copiedCommandToolId == tool.id ? Theme.successGreen : Theme.primaryIndigo)
                            
                            if copiedCommandToolId == tool.id {
                                Text("已複製")
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .foregroundColor(Theme.successGreen)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(copiedCommandToolId == tool.id ? Theme.successGreen.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("點擊複製終端機指令：\(cliUpgradeCommand(for: tool))")
                }
            }
            .frame(minWidth: 200, alignment: .leading)
            
            Spacer(minLength: 16)
            
            // 3. Right Side: Precision Fixed-Width Two-Tier Layout (Eliminating jagged alignment across rows)
            VStack(alignment: .trailing, spacing: 7) {
                // Top Tier: Fixed Column Status Pill (110pt) & Fixed Column Versions (130pt)
                HStack(spacing: 8) {
                    // Status Pill Column (Fixed 110pt width)
                    Group {
                        if tool.isInstalled {
                            if tool.isOutdated {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.warningAmber).frame(width: 5.5, height: 5.5)
                                    Text("可升級至 \(tool.latestVersion ?? "")")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Theme.warningAmber)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.warningAmber.opacity(0.12))
                                .clipShape(Capsule())
                            } else {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.successGreen).frame(width: 5.5, height: 5.5)
                                    Text("最新版本")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(Theme.successGreen)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.successGreen.opacity(0.12))
                                .clipShape(Capsule())
                            }
                        } else {
                            Text("未安裝")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.white.opacity(0.05))
                                .clipShape(Capsule())
                        }
                    }
                    .frame(width: 110, alignment: .trailing)
                    
                    // Versions Column (Fixed 130pt width with monospaced tabular digits)
                    HStack(spacing: 6) {
                        Text(tool.isInstalled ? tool.currentVersion : "—")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(tool.isInstalled ? .primary : .secondary)
                            .lineLimit(1)
                        
                        if let latest = tool.latestVersion, tool.isOutdated {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundColor(Theme.warningAmber)
                            
                            Text(latest)
                                .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(Theme.warningAmber)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .frame(width: 130, alignment: .trailing)
                }
                .frame(width: 250, alignment: .trailing)
                
                // Bottom Tier: Action Buttons (Consistently right-aligned in same 250pt frame)
                HStack(spacing: 8) {
                    // Primary Action: Download asset (if outdated or not yet installed)
                    if (tool.isOutdated || !tool.isInstalled), let url = InputValidator.httpsURL(tool.assetDownloadUrl, allowedHosts: ["github.com", "githubusercontent.com"]) {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 10.5))
                                Text(tool.assetName?.hasSuffix(".dmg") == true ? "下載 DMG" : "下載資產")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(Theme.primaryIndigo)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.bouncy(scale: 0.96))
                        .help("直接下載最新安裝檔：\(tool.assetName ?? "")")
                    }
                    
                    // GitHub Release Page
                    if let url = InputValidator.httpsURL(tool.htmlUrl, allowedHosts: ["github.com"]) {
                        Button(action: {
                            NSWorkspace.shared.open(url)
                        }) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .frame(width: 26, height: 26)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Theme.subtleBorder, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("在 GitHub 查看 Release 發布頁面")
                    }
                    
                    // Delete / Untrack
                    Button(action: {
                        withAnimation {
                            viewModel.removeTrackedGitHubTool(item: tool)
                        }
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.8))
                            .frame(width: 26, height: 26)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Theme.subtleBorder, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help("取消追蹤此項目")
                }
                .frame(width: 250, alignment: .trailing)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tool.isOutdated ? Theme.warningAmber.opacity(0.35) : Theme.subtleBorder, lineWidth: 1)
                )
        )
    }
    
    private func cliUpgradeCommand(for tool: GitHubToolItem) -> String {
        let rawName = tool.kind == .appBundle
            ? tool.binaryName.lowercased().replacingOccurrences(of: ".app", with: "")
            : tool.binaryName
        guard let name = InputValidator.safeName(rawName) else { return "" }
        return tool.kind == .appBundle ? "brew upgrade --cask \(name)" : "brew upgrade \(name)"
    }
    
    // MARK: - Empty State View
    
    // MARK: - Empty State View
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 34))
                .foregroundColor(.secondary.opacity(0.6))
            Text("目前沒有符合篩選條件的追蹤項目")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            Text("點擊上方「自動掃描 /Applications」可自動發掘本機已安裝之開源 Mac 應用程式，或點擊「新增追蹤」手動輸入儲存庫。")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 40)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Add Tool / App Sheet
    private var addToolSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Area
            VStack(alignment: .leading, spacing: 4) {
                Text("新增 GitHub 追蹤項目")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                Text("支援追蹤 GitHub Releases 上的 macOS 桌面應用程式 (.app) 或二進位 CLI 工具")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)
            
            Divider().background(Theme.subtleBorder)
            
            // Form Body
            VStack(alignment: .leading, spacing: 16) {
                // 1. 項目類型
                VStack(alignment: .leading, spacing: 6) {
                    Text("項目類型")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 6) {
                        Button(action: { newKind = .appBundle }) {
                            HStack(spacing: 5) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 11))
                                Text("macOS 桌面應用程式 (.app)")
                                    .font(.system(size: 11.5, weight: newKind == .appBundle ? .semibold : .medium))
                            }
                            .foregroundColor(newKind == .appBundle ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(newKind == .appBundle ? Theme.primaryIndigo : Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { newKind = .cli }) {
                            HStack(spacing: 5) {
                                Image(systemName: "terminal")
                                    .font(.system(size: 11))
                                Text("CLI 命令列工具")
                                    .font(.system(size: 11.5, weight: newKind == .cli ? .semibold : .medium))
                            }
                            .foregroundColor(newKind == .cli ? .white : .secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(newKind == .cli ? Theme.primaryIndigo : Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(3)
                    .background(Color.white.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
                }
                
                // 2. 本機路徑
                if newKind == .appBundle {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("本機應用程式 (.app)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("選填，綁定後可讀取圖示與現有版本")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        
                        HStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "macwindow")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                TextField("點右側瀏覽選擇或輸入路徑...", text: $selectedAppPath)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            .padding(.horizontal, 12)
                            .frame(height: 35)
                            .background(Color.white.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(Theme.subtleBorder, lineWidth: 1)
                            )
                            
                            Button(action: {
                                let panel = NSOpenPanel()
                                panel.allowedContentTypes = [.application]
                                panel.allowsMultipleSelection = false
                                panel.canChooseDirectories = false
                                panel.canChooseFiles = true
                                panel.directoryURL = URL(fileURLWithPath: "/Applications")
                                if panel.runModal() == .OK, let url = panel.url {
                                    selectedAppPath = url.path
                                    let (name, _, _) = GitHubToolService.shared.inspectAppBundle(at: url)
                                    if inputName.isEmpty { inputName = name }
                                }
                            }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "folder")
                                        .font(.system(size: 11.5))
                                    Text("瀏覽選擇...")
                                        .font(.system(size: 12, weight: .medium))
                                }
                                .padding(.horizontal, 12)
                                .frame(height: 35)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.bouncy)
                        }
                    }
                }
                
                // 3. GitHub 儲存庫
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("GitHub 儲存庫")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("必填")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundColor(Theme.primaryIndigo)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("例如: rxhanson/Rectangle 或完整網址", text: $inputRepo)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 35)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
                }
                
                // 4. 自訂名稱
                VStack(alignment: .leading, spacing: 6) {
                    Text(newKind == .appBundle ? "應用程式顯示名稱" : "二進位指令名稱")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "tag")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        TextField("選填，例如: Rectangle（留空則自動解析儲存庫名稱）", text: $inputName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 35)
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
                }
                
                if let err = errorMessage {
                    Text(err)
                        .font(.system(size: 11.5))
                        .foregroundColor(Theme.dangerRed)
                }
            }
            .padding(24)
            
            Divider().background(Theme.subtleBorder)
            
            // Footer Action Bar
            HStack(spacing: 12) {
                Spacer()
                
                Button("取消") {
                    showAddSheet = false
                }
                .keyboardShortcut(.cancelAction)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 16)
                .frame(height: 32)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
                .buttonStyle(.bouncy)
                
                Button(action: {
                    submitNewItem()
                }) {
                    HStack(spacing: 5) {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .bold))
                            Text("加入追蹤")
                                .font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .frame(height: 32)
                    .background(Theme.primaryGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 4, x: 0, y: 1)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.bouncy)
                .disabled(inputRepo.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.2))
        }
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .background(Theme.canvasBackground)
    }
    
    private func submitNewItem() {
        let cleaned = inputRepo
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: "http://github.com/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        
        let parts = cleaned.components(separatedBy: "/")
        guard parts.count >= 2 else {
            errorMessage = "請輸入正確的儲存庫格式 (例如: owner/repo)"
            return
        }
        
        let owner = parts[0]
        let repo = parts[1]
        let name = inputName.trimmingCharacters(in: .whitespaces).isEmpty ? repo : inputName.trimmingCharacters(in: .whitespaces)
        let appPath = selectedAppPath.trimmingCharacters(in: .whitespaces).isEmpty ? nil : selectedAppPath.trimmingCharacters(in: .whitespaces)
        
        isSubmitting = true
        errorMessage = nil
        
        Task {
            await viewModel.addTrackedGitHubItem(
                owner: owner,
                repo: repo,
                binaryName: name,
                kind: newKind,
                appPath: appPath
            )
            isSubmitting = false
            showAddSheet = false
        }
    }
}

import DevKeeperCore
import SwiftUI

public struct PackageRow: View {
    public let package: PackageItem
    public let isActionRunning: Bool
    public let onUpgrade: () -> Void
    public let onCleanUninstall: () -> Void
    
    @State private var isHovered = false
    @State private var showConfirmUninstall = false
    @State private var showDetailSheet = false
    @State private var copiedCommand = false
    @EnvironmentObject private var viewModel: AppViewModel
    
    private var isJustCompleted: Bool {
        viewModel.completedPackageId == package.id
    }
    
    public init(
        package: PackageItem,
        isActionRunning: Bool,
        onUpgrade: @escaping () -> Void,
        onCleanUninstall: @escaping () -> Void
    ) {
        self.package = package
        self.isActionRunning = isActionRunning
        self.onUpgrade = onUpgrade
        self.onCleanUninstall = onCleanUninstall
    }
    
    public var body: some View {
        HStack(alignment: .center, spacing: 14) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(iconTint.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(iconTint.opacity(0.2), lineWidth: 0.8)
                    )
                
                Image(systemName: package.type.sfSymbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(iconTint)
            }
            .fixedSize()
            
            // Name and description & update command
            VStack(alignment: .leading, spacing: 3) {
                Text(package.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let desc = package.description, !desc.isEmpty {
                    Text(desc)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                
                // Show update command chip if outdated with 1-click copy built-in
                if package.status.isOutdated {
                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(package.upgradeCommand, forType: .string)
                        copiedCommand = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                            copiedCommand = false
                        }
                    }) {
                        HStack(spacing: 5) {
                            Text("$")
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.primaryIndigo)
                            Text(package.upgradeCommand)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            
                            Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 9))
                                .foregroundColor(copiedCommand ? Theme.successGreen : Theme.primaryIndigo)
                            
                            if copiedCommand {
                                Text("已複製")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Theme.successGreen)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(copiedCommand ? Theme.successGreen.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("點擊複製更新指令：\(package.upgradeCommand)")
                }
            }
            .frame(minWidth: 160, alignment: .leading)
            
            Spacer(minLength: 16)
            
            // Precision-aligned Right Columns: Versions | Status | Actions
            HStack(spacing: 12) {
                // Version display with fixed-width column and monospaced tabular digits
                HStack(spacing: 6) {
                    Text(package.currentVersion)
                        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    if let latest = package.latestVersion, package.status.isOutdated {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text(latest)
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(width: 175, alignment: .trailing)
                
                let isCurrentUpdating = viewModel.isActionRunning && viewModel.currentActionPackageId == package.id
                
                // Status / Actions / Progress Bar Zone (Total width: 148pt, zero overlap guaranteed)
                Group {
                    if isCurrentUpdating || isJustCompleted {
                        VStack(alignment: .trailing, spacing: 3) {
                            HStack(spacing: 5) {
                                if isJustCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(Theme.successGreen)
                                        .font(.system(size: 11))
                                    Text("升級完成！")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(Theme.successGreen)
                                } else {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text(viewModel.actionStage.isEmpty ? "正在升級中..." : viewModel.actionStage)
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundColor(Theme.primaryIndigo)
                                        .lineLimit(1)
                                }
                                
                                Text("\(Int(viewModel.actionProgress * 100))%")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .monospacedDigit()
                                    .foregroundColor(isJustCompleted ? Theme.successGreen : .secondary)
                            }
                            
                            // Visual Animated Progress Bar
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .frame(height: 5)
                                    
                                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                        .fill(isJustCompleted ? Theme.successGreen : Theme.primaryIndigo)
                                        .frame(width: max(geo.size.width * CGFloat(viewModel.actionProgress), 8), height: 5)
                                }
                            }
                            .frame(width: 144, height: 5)
                        }
                        .frame(width: 148, alignment: .trailing)
                    } else {
                        HStack(spacing: 12) {
                            // Status Badge (Fixed 84pt)
                            StatusBadge(status: package.status)
                                .frame(width: 84, alignment: .center)
                            
                            // Action Button Slot (Fixed 52pt)
                            if isActionRunning {
                                ProgressView()
                                    .controlSize(.small)
                                    .frame(width: 52, alignment: .center)
                            } else if package.status.isOutdated {
                                Button(action: onUpgrade) {
                                    Text("更新")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 52, height: 26)
                                        .background(Theme.primaryGradient)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .shadow(color: Theme.primaryIndigo.opacity(0.3), radius: 3, x: 0, y: 1.5)
                                }
                                .buttonStyle(.bouncy)
                            } else {
                                Color.clear
                                    .frame(width: 52, height: 26)
                            }
                        }
                        .frame(width: 148, alignment: .trailing)
                    }
                }
                
                // Clean Uninstall Button (Fixed 26pt)
                Button(action: { showConfirmUninstall = true }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundColor(isHovered ? Theme.dangerRed : .secondary.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.bouncy)
                .help("乾淨移除此套件與相關殘留設定")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isJustCompleted ? Theme.successGreen.opacity(0.12) : (isHovered ? Theme.cardBackgroundHover : Theme.cardBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isJustCompleted ? Theme.successGreen.opacity(0.6) : (isHovered ? Theme.highlightBorder : Theme.subtleBorder), lineWidth: isJustCompleted ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            showDetailSheet = true
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                self.isHovered = hovering
            }
        }
        .help("點擊卡片查看 \(package.name) 的完整說明與更新資訊")
        .sheet(isPresented: $showDetailSheet) {
            PackageDetailSheet(package: package, viewModel: viewModel)
        }
        .confirmationDialog(
            "確定要乾淨移除 \(package.name) 嗎？",
            isPresented: $showConfirmUninstall,
            titleVisibility: .visible
        ) {
            Button("確認乾淨移除", role: .destructive) {
                onCleanUninstall()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(uninstallExplanation(for: package))
        }
    }
    
    private var iconTint: Color {
        switch package.type {
        case .npm: return Theme.infoCyan
        case .python: return Theme.successGreen
        case .brewFormula: return Theme.warningAmber
        case .brewCask: return Theme.primaryIndigo
        case .database: return Theme.purpleAccent
        }
    }
    
    private func uninstallExplanation(for package: PackageItem) -> String {
        switch package.type {
        case .brewCask:
            return "將連同該 App 留在系統 ~/Library/ 中的所有偏好設定、支援檔案與快取全數清除 (--zap)。"
        case .brewFormula:
            return "將移除該工具，並自動清除因其安裝但現在不再被需要的孤立依賴項目 (autoremove)。"
        case .npm:
            return "將自 Node.js 全域環境完全移除此 CLI 工具。"
        case .python:
            return "將自 Python 執行環境完全移除此套件。"
        case .database:
            return "將停止此資料庫服務並自 Homebrew 完全清除。"
        }
    }
}

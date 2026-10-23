import SwiftUI

public struct PackageDetailSheet: View {
    public let package: PackageItem
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var isFetchingDetails = false
    @State private var detailedNotes: String = ""
    @State private var showConfirmUninstall = false
    @State private var copiedCommandInSheet = false
    
    public init(package: PackageItem, viewModel: AppViewModel) {
        self.package = package
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Area
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(iconTint.opacity(0.12))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(iconTint.opacity(0.25), lineWidth: 1)
                        )
                    
                    Image(systemName: package.type.sfSymbol)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(iconTint)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(package.type.displayName)
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(24)
            .background(Color.white.opacity(0.02))
            
            Divider()
                .background(Theme.subtleBorder)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Version Comparison Box
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("目前本機版本")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(package.currentVersion)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(.primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("官方最新版本")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text(package.latestVersion ?? "檢查中...")
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .monospacedDigit()
                                .foregroundColor(package.status.isOutdated ? Theme.primaryIndigo : .primary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("升級狀態")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            StatusBadge(status: package.status)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    // Description Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("套件說明")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        Text(package.description?.isEmpty == false ? package.description! : "此套件官方未提供額外簡短描述。")
                            .font(.system(size: 12.5))
                            .foregroundColor(.secondary)
                            .lineSpacing(4)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    
                    // Terminal Update Command Section
                    VStack(alignment: .leading, spacing: 8) {
                        Text("終端機升級指令")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        
                        HStack(spacing: 10) {
                            HStack(spacing: 6) {
                                Text("$")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.primaryIndigo)
                                Text(package.upgradeCommand)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                            }
                            
                            Spacer()
                            
                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(package.upgradeCommand, forType: .string)
                                copiedCommandInSheet = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    copiedCommandInSheet = false
                                }
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: copiedCommandInSheet ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                    Text(copiedCommandInSheet ? "已複製" : "一鍵複製")
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundColor(copiedCommandInSheet ? Theme.successGreen : .primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                    }
                    
                    // Changelog / Release Notes Section
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("版本更新資訊與發布說明")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            if isFetchingDetails {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 6) {
                            if !detailedNotes.isEmpty {
                                Text(detailedNotes)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(3)
                            } else {
                                Text(package.status.isOutdated ?
                                     "此版本包含功能改進、錯誤修復與效能優化。點擊下方更新按鈕可直接升級至最新版本。" :
                                     "目前已是最新穩定版本，無需升級。")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(24)
            }
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Bottom Action Footer
            HStack(spacing: 12) {
                if let url = InputValidator.httpsURL(package.homepage) {
                    Link(destination: url) {
                        HStack(spacing: 5) {
                            Image(systemName: "safari")
                                .font(.system(size: 11.5))
                            Text("官方網站 / GitHub")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.bouncy)
                }
                
                Button(action: { showConfirmUninstall = true }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11.5))
                        Text("乾淨移除")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(Theme.dangerRed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Theme.dangerRed.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.bouncy)
                .disabled(viewModel.isActionRunning)
                
                Spacer()
                
                Button("關閉") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
                    .buttonStyle(.bouncy)
                
                if package.status.isOutdated {
                    Button(action: {
                        dismiss()
                        Task { await viewModel.upgradeSingle(package: package) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("立即升級至最新版")
                                .font(.system(size: 12.5, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Theme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 5, x: 0, y: 2)
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isActionRunning)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(red: 0.09, green: 0.10, blue: 0.12))
        }
        .frame(width: 540, height: 480)
        .background(Theme.canvasBackground)
        .confirmationDialog(
            "確定要乾淨移除 \(package.name) 嗎？",
            isPresented: $showConfirmUninstall,
            titleVisibility: .visible
        ) {
            Button("確認乾淨移除", role: .destructive) {
                dismiss()
                Task { await viewModel.cleanUninstall(package: package) }
            }
            Button("取消", role: .cancel) {}
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
}

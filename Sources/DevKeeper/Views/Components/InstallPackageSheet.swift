import DevKeeperCore
import SwiftUI

public struct InstallPackageSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    
    @State private var packageName: String = ""
    @State private var selectedType: PackageType = .npm
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header: Clean title without redundant close button (since Cancel button is at bottom)
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Theme.primaryIndigo.opacity(0.15))
                        .frame(width: 26, height: 26)
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.primaryIndigo)
                }
                Text("安裝新套件或工具")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Environment Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("目標安裝環境")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                VStack(spacing: 6) {
                    envRadioOption(type: .npm, title: "npm 全域工具", subtitle: "Node.js 全域 CLI（如 Claude Code）")
                    envRadioOption(type: .python, title: "Python 套件 (pip)", subtitle: "本機 Python 執行庫")
                    envRadioOption(type: .brewFormula, title: "Homebrew Formula", subtitle: "終端機命令列工具（如 ffmpeg, git）")
                    envRadioOption(type: .brewCask, title: "Homebrew Cask", subtitle: "macOS 視窗圖形應用程式")
                    envRadioOption(type: .database, title: "資料庫服務", subtitle: "PostgreSQL, Redis, MySQL 等")
                }
            }
            
            // Name Input
            VStack(alignment: .leading, spacing: 8) {
                Text("套件名稱")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Image(systemName: selectedType.sfSymbol)
                        .foregroundColor(Theme.primaryIndigo)
                        .font(.system(size: 12))
                    
                    TextField(placeholderText, text: $packageName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.highlightBorder, lineWidth: 1)
                )
            }
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Action Buttons
            HStack(spacing: 12) {
                Spacer()
                
                Button("取消") {
                    dismiss()
                }
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
                
                Button(action: {
                    let name = packageName.trimmingCharacters(in: .whitespaces)
                    let type = selectedType
                    dismiss()
                    Task {
                        await viewModel.installNewPackage(name: name, type: type)
                    }
                }) {
                    Text("開始完整安裝")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 32)
                        .background(Theme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 4, x: 0, y: 1)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.bouncy)
                .disabled(packageName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isActionRunning)
            }
        }
        .padding(24)
        .frame(width: 440)
        .background(Theme.canvasBackground)
    }
    
    private func envRadioOption(type: PackageType, title: String, subtitle: String) -> some View {
        let isSelected = selectedType == type
        
        return Button(action: {
            withAnimation(.easeOut(duration: 0.12)) {
                selectedType = type
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: type.sfSymbol)
                    .foregroundColor(isSelected ? Theme.primaryIndigo : .secondary)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary.opacity(0.8))
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Theme.primaryIndigo)
                        .font(.system(size: 12))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(isSelected ? Theme.primaryIndigo.opacity(0.12) : Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? Theme.primaryIndigo.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var placeholderText: String {
        switch selectedType {
        case .npm: return "例如：@anthropic-ai/claude-code"
        case .python: return "例如：httpx, rich, jupyter"
        case .brewFormula: return "例如：ffmpeg, wget"
        case .brewCask: return "例如：visual-studio-code"
        case .database: return "例如：postgresql@16, redis"
        }
    }
}

import SwiftUI
import AppKit

/// Lists project virtual environments and lets the user rebuild old ones with a supported Python.
struct ProjectVenvSection: View {
    @ObservedObject var viewModel: AppViewModel
    
    private var staleCount: Int { viewModel.projectVenvs.filter { $0.isEndOfLife }.count }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.primaryIndigo)
                Text("專案虛擬環境")
                    .font(.system(size: 13.5, weight: .bold))
                Text("\(viewModel.projectVenvs.count) 個")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                if staleCount > 0 {
                    badge("\(staleCount) 個使用已終止支援的 Python", tint: Theme.dangerRed)
                }
                Spacer()
                if viewModel.isScanningVenvs { ProgressView().controlSize(.small) }
                pillButton(viewModel.projectsRoot.isEmpty ? "選擇專案資料夾" : "重新掃描", icon: viewModel.projectsRoot.isEmpty ? "folder" : "arrow.clockwise") {
                    if viewModel.projectsRoot.isEmpty { chooseFolder() } else { Task { await viewModel.scanProjectVenvs() } }
                }
                .disabled(viewModel.isScanningVenvs || viewModel.isActionRunning)
            }
            
            Text("每個專案的虛擬環境是用建立當時的 Python 版本做的。版本太舊時，可以用新版 Python 重建並重新安裝套件；舊環境會先保留備份，重建失敗會自動還原。")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            if viewModel.projectsRoot.isEmpty {
                Text("尚未設定本機專案資料夾。選擇你放專案的資料夾後，DevKeeper 才能找出裡面的虛擬環境。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            } else if viewModel.projectVenvs.isEmpty && !viewModel.isScanningVenvs {
                Text("在 \(viewModel.projectsRoot) 裡沒有找到虛擬環境（.venv、venv、env）。")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
            
            VStack(spacing: 6) {
                ForEach(viewModel.projectVenvs) { venv in row(venv) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.subtleBorder, lineWidth: 1))
        .task { await viewModel.scanProjectVenvs() }
    }
    
    private func row(_ venv: ProjectVenv) -> some View {
        let rebuilding = viewModel.rebuildingVenvPath == venv.id
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(venv.projectName)
                            .font(.system(size: 12.5, weight: .semibold))
                        badge("Python \(venv.pythonVersion)", tint: .secondary)
                        switch PythonLifecycle.status(forMinor: venv.minorVersion) {
                        case .endOfLife(let d): badge("已終止支援 \(d)", tint: Theme.dangerRed)
                        case .endingSoon(let d): badge("支援至 \(d)", tint: Theme.warningAmber)
                        case .supported: EmptyView()
                        }
                    }
                    Text(venv.venvPath)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(.secondary.opacity(0.8))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                if rebuilding {
                    HStack(spacing: 5) {
                        ProgressView().controlSize(.small)
                        Text("重建中").font(.system(size: 11.5, weight: .semibold))
                    }
                    .frame(width: 110)
                    .padding(.vertical, 5)
                    .background(Theme.primaryIndigo.opacity(0.25))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if venv.minorVersion.compare(PythonLifecycle.recommendedMinor, options: .numeric) == .orderedAscending {
                    Button(action: { Task { await viewModel.rebuildVenv(venv) } }) {
                        Text("用 \(PythonLifecycle.recommendedMinor) 重建")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 110)
                            .padding(.vertical, 5)
                            .background(venv.isEndOfLife ? AnyShapeStyle(Theme.primaryGradient) : AnyShapeStyle(Color.white.opacity(0.12)))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isActionRunning)
                } else {
                    Text("已是建議版本")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            if let message = viewModel.venvMessages[venv.id] {
                HStack(alignment: .top, spacing: 6) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if viewModel.venvBackups[venv.id] != nil {
                        pillButton("刪除舊環境備份", icon: "trash") { viewModel.deleteVenvBackup(for: venv) }
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.subtleBorder, lineWidth: 1))
    }
    
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "選擇專案資料夾"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await viewModel.setProjectsRoot(url.path) }
        }
    }
    
    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .bold))
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(tint.opacity(0.14))
            .clipShape(Capsule())
    }
    
    private func pillButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.bouncy)
    }
}

import SwiftUI

/// Sidebar page: every Python interpreter on this Mac, its support status, and tools to update and manage them.
public struct PythonVersionsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var supportedCount: Int { viewModel.pythonInterpreters.filter { !$0.isEndOfLife }.count }
    private var endOfLifeCount: Int { viewModel.endOfLifePythons.count }
    private var upgradableCount: Int {
        viewModel.pythonInterpreters.filter { viewModel.upgradeTarget(for: $0) != nil }.count
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            header
            
            Divider()
                .background(Theme.subtleBorder)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 10) {
                        statCard("已安裝版本", count: viewModel.pythonInterpreters.count, symbol: "square.stack.3d.up", tint: Theme.primaryIndigo)
                        statCard("支援中", count: supportedCount, symbol: "checkmark.shield", tint: Theme.successGreen)
                        statCard("已終止支援", count: endOfLifeCount, symbol: "exclamationmark.triangle", tint: endOfLifeCount > 0 ? Theme.dangerRed : .secondary)
                        statCard("可升級", count: upgradableCount, symbol: "arrow.up.circle", tint: upgradableCount > 0 ? Theme.warningAmber : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 14) {
                        PythonEnvironmentCard(viewModel: viewModel)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Theme.subtleBorder, lineWidth: 1)
                    )
                    
                    Text("提示：升級後的新版本是安裝在舊版本旁邊，不會取代它。舊版本裡的套件需要在「安全弱點稽核」用「搬到獨立環境」或「移除套件」處理。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
            }
        }
    }
    
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(Theme.primaryIndigo)
                    
                    Text("Python 版本")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text("\(viewModel.pythonInterpreters.count) 個版本")
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                }
                
                Text("本機所有 Python 版本、支援狀態，以及升級、安裝與選用")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button(action: {
                Task { await viewModel.scanPythonInterpreters() }
            }) {
                HStack(spacing: 5) {
                    if viewModel.isScanningPython {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("重新偵測")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .buttonStyle(.bouncy)
            .disabled(viewModel.isScanningPython || viewModel.isActionRunning)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
    }
    
    private func statCard(_ title: String, count: Int, symbol: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 30, height: 30)
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(tint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                Text("\(count)")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
        )
    }
}

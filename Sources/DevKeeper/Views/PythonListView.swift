import SwiftUI

public struct PythonListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText: String = ""
    @State private var onlyOutdated: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredPackages: [PackageItem] {
        viewModel.pythonPackages.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.description ?? "").localizedCaseInsensitiveContains(searchText)
            
            let matchesOutdated = !onlyOutdated || item.status.isOutdated
            return matchesSearch && matchesOutdated
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Row 1: Header Title & Action Buttons
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text("Python 套件 (pip)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("\(viewModel.pythonPackages.count) 個套件")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    
                    Text("管理本機 Python 執行環境安裝之第三方庫與 CLI 工具")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(action: { viewModel.showInstallSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("安裝套件")
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isActionRunning)
                    
                    Button(action: {
                        Task { await viewModel.scanPython() }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("重新檢查")
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isScanning || viewModel.isActionRunning)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            
            // Row 2: Search & Filter Pill
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11.5))
                    TextField("搜尋 Python 套件 (pip)...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 260)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Theme.cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeOut(duration: 0.12)) {
                        onlyOutdated.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(onlyOutdated ? Theme.warningAmber : .secondary.opacity(0.8))
                        Text("僅待升級 (\(viewModel.outdatedPythonCount))")
                            .font(.system(size: 11.5, weight: onlyOutdated ? .semibold : .medium))
                            .foregroundColor(onlyOutdated ? Theme.warningAmber : .primary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(onlyOutdated ? Theme.warningAmber.opacity(0.14) : Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(onlyOutdated ? Theme.warningAmber.opacity(0.4) : Theme.subtleBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(.bouncy(scale: 0.97))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Content List
            if viewModel.isScanning && viewModel.pythonPackages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在檢查 Python 套件與 PyPI 版本...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPackages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "未找到 Python 套件" : "無符合搜尋條件的套件")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filteredPackages) { item in
                            PackageRow(
                                package: item,
                                isActionRunning: viewModel.currentActionPackageId == item.id,
                                onUpgrade: {
                                    Task { await viewModel.upgradeSingle(package: item) }
                                },
                                onCleanUninstall: {
                                    Task { await viewModel.cleanUninstall(package: item) }
                                }
                            )
                        }
                    }
                    .padding(24)
                }
            }
        }
        .background(Theme.canvasBackground)
    }
}

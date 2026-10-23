import SwiftUI

public struct NpmListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText: String = ""
    @State private var filterIndex: Int = 0 // 0: All, 1: Outdated Only
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredPackages: [PackageItem] {
        viewModel.npmPackages.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.description ?? "").localizedCaseInsensitiveContains(searchText)
            
            let matchesFilter = filterIndex == 0 ? true : item.status.isOutdated
            return matchesSearch && matchesFilter
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Row 1: Header Title & Action Buttons
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "cube")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text("全域 npm 套件")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("\(viewModel.npmPackages.count) 個套件")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    
                    Text("管理 Node.js 全域安裝之命令列工具 (包含 Claude Code 等)")
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
                        Task { await viewModel.scanNpm() }
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
                    
                    if viewModel.outdatedNpmCount > 0 {
                        Button(action: {
                            Task { await viewModel.upgradeAllOutdatedNpm() }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .bold))
                                HStack(spacing: 0) {
                                    Text("更新全部 (")
                                    Text("\(viewModel.outdatedNpmCount)")
                                        .monospacedDigit()
                                    Text(")")
                                }
                                .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Theme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .shadow(color: Theme.primaryIndigo.opacity(0.4), radius: 5, x: 0, y: 2)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.bouncy)
                        .disabled(viewModel.isActionRunning || viewModel.isScanning)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            
            // Row 2: Search & Filter Tabs
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11.5))
                    TextField("搜尋全域 npm 套件...", text: $searchText)
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
                
                // Custom Styled Category Filter
                HStack(spacing: 3) {
                    ForEach([("全部 (\(viewModel.npmPackages.count))", 0), ("僅待升級 (\(viewModel.outdatedNpmCount))", 1)], id: \.1) { (title, tag) in
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.12)) {
                                filterIndex = tag
                            }
                        }) {
                            Text(title)
                                .font(.system(size: 11.5, weight: filterIndex == tag ? .semibold : .medium))
                                .foregroundColor(filterIndex == tag ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(filterIndex == tag ? Theme.primaryIndigo : Color.white.opacity(0.03))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(3)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Content List
            if viewModel.isScanning && viewModel.npmPackages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在檢查 npm 全域套件與官方版本...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPackages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "cube")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "未找到全域 npm 套件" : "無符合搜尋條件的套件")
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

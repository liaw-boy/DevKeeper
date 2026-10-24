import DevKeeperCore
import SwiftUI

public struct BrewListView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var searchText: String = ""
    @State private var selectedType: Int = 0 // 0: All, 1: Formulae, 2: Casks
    @State private var onlyOutdated: Bool = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var filteredPackages: [PackageItem] {
        viewModel.brewPackages.filter { item in
            let matchesSearch = searchText.isEmpty ||
                item.name.localizedCaseInsensitiveContains(searchText) ||
                (item.description ?? "").localizedCaseInsensitiveContains(searchText)
            
            let matchesType: Bool
            switch selectedType {
            case 1: matchesType = item.type == .brewFormula
            case 2: matchesType = item.type == .brewCask
            default: matchesType = true
            }
            
            let matchesOutdated = !onlyOutdated || item.status.isOutdated
            return matchesSearch && matchesType && matchesOutdated
        }
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Top Section (Row 1: Header Title & Action Buttons)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "shippingbox")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text("Homebrew 軟體與工具")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("\(viewModel.brewPackages.count) 個項目")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    
                    Text("管理命令列工具 (Formulae) 與 Mac 應用程式 (Casks)")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Action Buttons
                HStack(spacing: 10) {
                    Button(action: { viewModel.showInstallSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("安裝軟體")
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
                        Task { await viewModel.scanBrew() }
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
                    
                    if viewModel.outdatedBrewCount > 0 {
                        Button(action: {
                            Task { await viewModel.upgradeAllOutdatedBrew() }
                        }) {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11, weight: .bold))
                                HStack(spacing: 0) {
                                    Text("更新全部 (")
                                    Text("\(viewModel.outdatedBrewCount)")
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
            
            // Row 2: Search Bar & Segmented Filters (Generous spacing, no overlap!)
            HStack(spacing: 16) {
                // Search Input
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11.5))
                    TextField("搜尋 Homebrew 套件...", text: $searchText)
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
                
                // Custom Styled Category Filter (Replacing legacy AppKit segmented control)
                HStack(spacing: 3) {
                    ForEach([("全部", 0), ("命令列 (CLI)", 1), ("應用程式 (Cask)", 2)], id: \.1) { (title, tag) in
                        Button(action: {
                            withAnimation(.easeOut(duration: 0.12)) {
                                selectedType = tag
                            }
                        }) {
                            Text(title)
                                .font(.system(size: 11.5, weight: selectedType == tag ? .semibold : .medium))
                                .foregroundColor(selectedType == tag ? .white : .secondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(selectedType == tag ? Theme.primaryIndigo : Color.white.opacity(0.03))
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
                
                // Modern Outdated Filter Chip (Consistent with Overview style)
                Button(action: {
                    withAnimation(.easeOut(duration: 0.12)) {
                        onlyOutdated.toggle()
                    }
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(onlyOutdated ? Theme.warningAmber : .secondary.opacity(0.8))
                        Text("僅待升級 (\(viewModel.outdatedBrewCount))")
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
            if viewModel.isScanning && viewModel.brewPackages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("正在檢查 Homebrew 套件與可用更新...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredPackages.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 30))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(searchText.isEmpty ? "未找到符合的 Homebrew 套件" : "無符合搜尋條件的套件")
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

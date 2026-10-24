import DevKeeperCore
import SwiftUI

public struct DatabaseListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar (Standardized 20pt Bold + Icon + Badge + 11.5pt Subtitle)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "cylinder.split.1x2")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text("本機資料庫與服務狀態")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("\(viewModel.databaseServices.count) 個服務")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    
                    Text("管理 Homebrew 背景資料庫服務之生命週期與版本")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                HStack(spacing: 10) {
                    Button(action: { viewModel.showInstallSheet = true }) {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                            Text("安裝資料庫")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isActionRunning)
                    
                    Button(action: {
                        Task { await viewModel.scanDatabases() }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                            Text("重新整理")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(Theme.subtleBorder, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isScanning || viewModel.isActionRunning)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            
            Divider()
                .background(Theme.subtleBorder)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // Running & Installed Services Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.primaryIndigo)
                            Text("已運行之資料庫服務")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        if viewModel.databaseServices.isEmpty {
                            HStack {
                                Spacer()
                                VStack(spacing: 8) {
                                    Image(systemName: "cylinder.split.1x2")
                                        .font(.system(size: 28))
                                        .foregroundColor(.secondary.opacity(0.6))
                                    Text("目前未偵測到運作中或已安裝之資料庫服務")
                                        .font(.system(size: 12.5))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 36)
                                Spacer()
                            }
                            .background(Theme.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.subtleBorder, lineWidth: 1)
                            )
                        } else {
                            VStack(spacing: 9) {
                                ForEach(viewModel.databaseServices) { service in
                                    databaseRow(service: service)
                                }
                            }
                        }
                    }
                    
                    // Quick Install Common Databases
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Theme.warningAmber)
                            Text("常用資料庫一鍵安裝推薦")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(DatabaseService.commonDatabases.sorted(by: { $0.key < $1.key }), id: \.key) { key, desc in
                                let isInstalled = viewModel.databaseServices.contains(where: { $0.name == key })
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(key)
                                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.primary)
                                        Text(desc)
                                            .font(.system(size: 11))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    if isInstalled {
                                        Text("已就緒")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(Theme.successGreen)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 3.5)
                                            .background(Theme.successGreen.opacity(0.12))
                                            .clipShape(Capsule())
                                    } else {
                                        Button("安裝") {
                                            Task {
                                                await viewModel.installNewPackage(name: key, type: .database)
                                            }
                                        }
                                        .font(.system(size: 11.5, weight: .medium))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.06))
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                        .buttonStyle(.plain)
                                        .disabled(viewModel.isActionRunning)
                                    }
                                }
                                .padding(14)
                                .background(Theme.cardBackground)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Theme.subtleBorder, lineWidth: 1)
                                )
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .background(Theme.canvasBackground)
    }
    
    private func databaseRow(service: DatabaseServiceItem) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.purpleAccent.opacity(0.12))
                    .frame(width: 34, height: 34)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.purpleAccent.opacity(0.2), lineWidth: 0.8)
                    )
                
                Image(systemName: "cylinder.split.1x2")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Theme.purpleAccent)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)
                
                if let file = service.file {
                    Text(file)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Status Indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(service.status == .started ? Theme.successGreen : Color.secondary.opacity(0.4))
                    .frame(width: 7, height: 7)
                Text(service.status.localizedTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(service.status == .started ? Theme.successGreen : Color.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background((service.status == .started ? Theme.successGreen : Color.secondary).opacity(0.12))
            .clipShape(Capsule())
            
            // Control Actions
            HStack(spacing: 6) {
                if service.status == .started {
                    Button(action: {
                        Task { await viewModel.controlDatabaseService(name: service.name, action: "stop") }
                    }) {
                        Text("停止")
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isActionRunning)
                    
                    Button(action: {
                        Task { await viewModel.controlDatabaseService(name: service.name, action: "restart") }
                    }) {
                        Text("重啟")
                            .font(.system(size: 11.5, weight: .medium))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isActionRunning)
                } else {
                    Button(action: {
                        Task { await viewModel.controlDatabaseService(name: service.name, action: "start") }
                    }) {
                        Text("啟動")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Theme.primaryGradient)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isActionRunning)
                }
                
                // Clean Uninstall Database
                Button(action: {
                    Task {
                        let item = PackageItem(name: service.name, currentVersion: "", type: .database)
                        await viewModel.cleanUninstall(package: item)
                    }
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary.opacity(0.7))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("乾淨移除此資料庫與服務")
                .disabled(viewModel.isActionRunning)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }
}

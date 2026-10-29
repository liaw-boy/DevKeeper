import DevKeeperCore
import SwiftUI

public struct DatabaseListView: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var runningCount: Int { viewModel.databaseServices.filter { $0.status == .started }.count }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DKPageHeader(
                    "資料庫",
                    subtitle: "本機 Homebrew 管理的資料庫服務",
                    count: viewModel.databaseServices.isEmpty ? nil : "\(runningCount) 個運行中"
                ) {
                    DKButton("安裝", systemImage: "plus") { viewModel.showInstallSheet = true }
                        .disabled(viewModel.isActionRunning)
                    DKButton("重新檢查", systemImage: "arrow.clockwise") {
                        Task { await viewModel.scanDatabases() }
                    }
                    .disabled(viewModel.isScanning || viewModel.isActionRunning)
                }
                
                VStack(alignment: .leading, spacing: DK.Space.xl) {
                    VStack(alignment: .leading, spacing: DK.Space.m) {
                        DKSectionTitle("已安裝的服務")
                        if viewModel.databaseServices.isEmpty {
                            DKEmptyState(kind: viewModel.isScanning ? .loading : .empty,
                                         title: viewModel.isScanning ? "正在偵測資料庫服務…" : "沒有偵測到資料庫服務",
                                         message: viewModel.isScanning ? nil : "從下方挑一個常用的資料庫安裝。")
                                .dkCard(padding: 0)
                        } else {
                            VStack(spacing: DK.Space.s) {
                                ForEach(viewModel.databaseServices) { service in
                                    serviceRow(service)
                                }
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: DK.Space.m) {
                        DKSectionTitle("常用資料庫")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: DK.Space.s), GridItem(.flexible(), spacing: DK.Space.s)],
                                  spacing: DK.Space.s) {
                            ForEach(DatabaseService.commonDatabases.sorted(by: { $0.key < $1.key }), id: \.key) { key, desc in
                                suggestion(name: key, description: desc)
                            }
                        }
                    }
                }
                .padding(.horizontal, DK.pagePadding)
                .padding(.bottom, DK.pagePadding)
            }
        }
        .background(DK.background)
    }
    
    private func suggestion(name: String, description: String) -> some View {
        let installed = viewModel.databaseServices.contains { $0.name == name }
        return HStack(spacing: DK.Space.m) {
            DKSourceBadge(.database, size: 32)
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                Text(name)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                Text(description)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: DK.Space.s)
            if installed {
                Text("已安裝")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textTertiary)
            } else {
                DKButton("安裝", disabledReason: viewModel.isActionRunning ? "正在執行其他操作" : nil) {
                    Task { await viewModel.installNewPackage(name: name, type: .database) }
                }
                .disabled(viewModel.isActionRunning)
            }
        }
        .padding(.vertical, DK.Space.s)
        .padding(.horizontal, DK.Space.m)
        .frame(maxWidth: .infinity)
        .dkCard(padding: 0)
    }
    
    private func serviceRow(_ service: DatabaseServiceItem) -> some View {
        let running = service.status == .started
        let busy = viewModel.isActionRunning
        return HStack(spacing: DK.Space.m) {
            DKSourceBadge(.database, size: 32)
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                Text(service.name)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                if let file = service.file {
                    Text(file)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: DK.Space.l)
            if DatabaseService.isRunnableService(service.name) {
                HStack(spacing: DK.Space.xs) {
                    Circle()
                        .fill(running ? DK.success : DK.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(service.status.localizedTitle)
                        .font(DK.Font.caption)
                        .foregroundColor(running ? DK.success : DK.textSecondary)
                }
                if running {
                    DKButton("停止", disabledReason: busy ? "正在執行其他操作" : nil) {
                        Task { await viewModel.controlDatabaseService(name: service.name, action: "stop") }
                    }
                    .disabled(busy)
                    DKButton("重啟", disabledReason: busy ? "正在執行其他操作" : nil) {
                        Task { await viewModel.controlDatabaseService(name: service.name, action: "restart") }
                    }
                    .disabled(busy)
                } else {
                    DKButton("啟動", kind: .primary, disabledReason: busy ? "正在執行其他操作" : nil) {
                        Task { await viewModel.controlDatabaseService(name: service.name, action: "start") }
                    }
                    .disabled(busy)
                }
            } else {
                Text("內嵌式，沒有服務可啟動")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textTertiary)
            }
            DKIconButton("trash", help: "移除 \(service.name)", compact: true) {
                let item = PackageItem(name: service.name, currentVersion: "", type: .database)
                overlay?.confirm(
                    "移除 \(service.name)？",
                    message: "會先停止服務再解除安裝，資料目錄不會被刪除。",
                    commands: item.uninstallCommands,
                    confirmTitle: "移除",
                    destructive: true
                ) {
                    Task { await viewModel.cleanUninstall(package: item) }
                }
            }
            .disabled(busy)
        }
        .padding(.vertical, DK.Space.s)
        .padding(.horizontal, DK.Space.m)
        .dkCard(padding: 0)
    }
}

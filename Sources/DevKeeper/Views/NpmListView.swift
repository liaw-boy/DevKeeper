import DevKeeperCore
import SwiftUI

public struct NpmListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        PackageListPage(
            viewModel: viewModel,
            title: "npm",
            subtitle: "Node.js 全域安裝的命令列工具",
            noun: "npm 套件",
            packages: viewModel.npmPackages,
            outdatedCount: viewModel.outdatedNpmCount,
            upgradeAll: NpmService.upgradeAllCommand(packages: viewModel.npmPackages.filter { $0.status.isOutdated }.map(\.name)).map {
                PackageUpgradeAll(commands: [$0]) { await viewModel.upgradeAllOutdatedNpm() }
            }
        )
    }
}

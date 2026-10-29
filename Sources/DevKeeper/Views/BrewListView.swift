import DevKeeperCore
import SwiftUI

public struct BrewListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    private enum Kind: Hashable { case all, formula, cask }
    @State private var kind: Kind = .all
    /// Dependencies are hidden by default: most of a long Homebrew list is packages the user never chose.
    @State private var showDependencies = false
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var dependencyCount: Int { viewModel.brewPackages.filter(\.isDependencyOnly).count }
    
    private var upgradeAll: PackageUpgradeAll? {
        let names = viewModel.outdatedBrewNames
        return BrewService.upgradeCommands(formulae: names.formulae, casks: names.casks).map {
            PackageUpgradeAll(commands: $0) { await viewModel.upgradeAllOutdatedBrew() }
        }
    }
    
    public var body: some View {
        PackageListPage(
            viewModel: viewModel,
            title: "Homebrew",
            subtitle: "命令列工具（Formula）與應用程式（Cask）",
            noun: "Homebrew 套件",
            packages: viewModel.brewPackages,
            outdatedCount: viewModel.outdatedBrewCount,
            upgradeAll: upgradeAll,
            extraFilter: { item in
                switch kind {
                case .all: break
                case .formula: if item.type != .brewFormula { return false }
                case .cask: if item.type != .brewCask { return false }
                }
                // Outdated dependencies stay visible so an update is never hidden.
                return showDependencies || !item.isDependencyOnly || item.status.isOutdated
            }
        ) {
            DKDropdown(options: [(Kind.all, "全部類型"), (.formula, "命令列"), (.cask, "應用程式")], selection: $kind)
            if dependencyCount > 0 {
                DKButton(showDependencies ? "隱藏相依套件" : "顯示相依套件（\(dependencyCount)）",
                         systemImage: showDependencies ? "eye.slash" : "eye", kind: .ghost) {
                    showDependencies.toggle()
                }
                .dkTooltip("只因為其他套件需要才裝的套件。預設隱藏；有待更新的仍會顯示。")
            }
        }
    }
}

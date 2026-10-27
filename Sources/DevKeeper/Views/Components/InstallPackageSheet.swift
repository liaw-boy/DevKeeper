import DevKeeperCore
import SwiftUI

/// Installs a package by name. Presented as a modal panel; `InstallPresenter` opens it when
/// `AppViewModel.showInstallSheet` is set.
public struct InstallPackageSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay
    
    @State private var packageName: String
    @State private var selectedType: PackageType
    
    public init(viewModel: AppViewModel, initialType: PackageType = .npm) {
        self.viewModel = viewModel
        _packageName = State(initialValue: "")
        _selectedType = State(initialValue: initialType)
    }
    
    private var trimmedName: String { packageName.trimmingCharacters(in: .whitespacesAndNewlines) }
    
    private var nameIsValid: Bool { InputValidator.isValidPackageName(trimmedName) }
    
    public var body: some View {
        DKModalPanel("安裝套件", subtitle: "從所選來源安裝，安裝過程會顯示在執行日誌。", width: 460) {
            VStack(alignment: .leading, spacing: DK.Space.l) {
                VStack(alignment: .leading, spacing: DK.Space.s) {
                    Text("來源")
                        .font(DK.Font.bodyMedium)
                        .foregroundColor(DK.textPrimary)
                    DKDropdown(options: [
                        (PackageType.npm, "npm 全域工具"),
                        (.python, "Python 套件（pip）"),
                        (.uvTool, "uv 工具"),
                        (.brewFormula, "Homebrew 命令列工具"),
                        (.brewCask, "Homebrew 應用程式"),
                        (.database, "資料庫服務")
                    ], selection: $selectedType)
                    Text(hint)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textTertiary)
                }
                
                VStack(alignment: .leading, spacing: DK.Space.s) {
                    Text("套件名稱")
                        .font(DK.Font.bodyMedium)
                        .foregroundColor(DK.textPrimary)
                    DKTextField(placeholder: placeholderText, text: $packageName, systemImage: selectedType.sfSymbol)
                    if !trimmedName.isEmpty && !nameIsValid {
                        Text("名稱只能包含英數字、底線、連字號、點、@ 和斜線。")
                            .font(DK.Font.caption)
                            .foregroundColor(DK.danger)
                    }
                }
            }
        } footer: {
            DKButton("取消") { overlay?.dismissModal() }
            DKButton("安裝", kind: .primary,
                     disabledReason: viewModel.isActionRunning ? "正在執行其他操作" : nil) {
                let name = trimmedName
                let type = selectedType
                overlay?.dismissModal()
                Task { await viewModel.installNewPackage(name: name, type: type) }
            }
            .disabled(!nameIsValid || viewModel.isActionRunning)
        }
    }
    
    private var hint: String {
        switch selectedType {
        case .npm: return "Node.js 全域命令列工具，例如 Claude Code。"
        case .python: return "安裝到目前使用的 Python 直譯器。"
        case .brewFormula: return "終端機工具，例如 ffmpeg、git。"
        case .brewCask: return "macOS 圖形應用程式。"
        case .database: return "PostgreSQL、Redis、MySQL 等，透過 Homebrew 安裝。"
        case .uvTool: return "用 uv 安裝成獨立環境的 Python 命令列工具，需要先安裝 uv。"
        }
    }
    
    private var placeholderText: String {
        switch selectedType {
        case .npm: return "例如 @anthropic-ai/claude-code"
        case .python: return "例如 httpx"
        case .brewFormula: return "例如 ffmpeg"
        case .brewCask: return "例如 visual-studio-code"
        case .database: return "例如 postgresql@16"
        case .uvTool: return "例如 ruff"
        }
    }
}

/// Opens the install panel when the view model asks for it. Lives inside the overlay host so it can present.
struct InstallPresenter: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay
    
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .task {
                // Development aid for screenshots: open a panel without clicking.
                guard let what = ProcessInfo.processInfo.environment["DEVKEEPER_OPEN"] else { return }
                try? await Task.sleep(nanoseconds: 7_000_000_000)
                switch what {
                case "install":
                    overlay?.present { InstallPackageSheet(viewModel: viewModel) }
                case "detail":
                    if let item = viewModel.brewPackages.first(where: { $0.status.isOutdated }) ?? viewModel.brewPackages.first {
                        overlay?.present { PackageDetailSheet(package: item, viewModel: viewModel) }
                    }
                default: break
                }
            }
            .onChange(of: viewModel.showInstallSheet) { _, show in
                guard show else { return }
                // The flag is only a trigger; clear it so the next request fires again after Esc or a scrim click.
                viewModel.showInstallSheet = false
                let initial: PackageType
                switch viewModel.selectedTab {
                case .python: initial = .python
                case .brew: initial = .brewFormula
                case .database: initial = .database
                default: initial = .npm
                }
                overlay?.present { InstallPackageSheet(viewModel: viewModel, initialType: initial) }
            }
    }
}

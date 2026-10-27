import DevKeeperCore
import SwiftUI

public struct PythonListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var interpreter: PythonInterpreter? {
        viewModel.pythonInterpreters.first { $0.path == viewModel.selectedPythonPath }
    }
    
    private var subtitle: String {
        guard let interpreter else { return "目前使用的 Python 直譯器上安裝的套件" }
        return "Python \(interpreter.version)（\(interpreter.source.rawValue)）· \(interpreter.path)"
    }
    
    public var body: some View {
        PackageListPage(
            viewModel: viewModel,
            title: "Python",
            subtitle: subtitle,
            noun: "Python 套件",
            notice: interpreter?.isExternallyManaged == true
                ? "這個直譯器受系統套件管理器保護（PEP 668），pip 不允許寫入，所以只能查看，不能更新或移除。"
                : nil,
            packages: viewModel.pythonPackages,
            outdatedCount: viewModel.outdatedPythonCount
        )
    }
}

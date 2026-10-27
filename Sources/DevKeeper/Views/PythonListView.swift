import DevKeeperCore
import SwiftUI

public struct PythonListView: View {
    @ObservedObject var viewModel: AppViewModel
    
    private enum Mode: Hashable { case pip, uv }
    @State private var mode: Mode
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
        // Development aid for screenshots: DEVKEEPER_PYTHON_MODE=uv opens on the uv tools list.
        _mode = State(initialValue: ProcessInfo.processInfo.environment["DEVKEEPER_PYTHON_MODE"] == "uv" ? .uv : .pip)
    }
    
    private var interpreter: PythonInterpreter? {
        viewModel.pythonInterpreters.first { $0.path == viewModel.selectedPythonPath }
    }
    
    private var subtitle: String {
        if mode == .uv { return "用 uv tool install 安裝的獨立命令列工具，各有自己的環境" }
        guard let interpreter else { return "目前使用的 Python 直譯器上安裝的套件" }
        return "Python \(interpreter.version)（\(interpreter.source.rawValue)）· \(interpreter.path)"
    }
    
    /// Explains an empty or partial list, so "nothing installed" is never confused with "could not look".
    private var notice: String? {
        switch mode {
        case .pip:
            return interpreter?.isExternallyManaged == true
                ? "這個直譯器受系統套件管理器保護（PEP 668），pip 不允許寫入，所以只能查看，不能更新或移除。"
                : nil
        case .uv:
            switch viewModel.uvScanState {
            case .notInstalled: return "這台電腦沒有安裝 uv，所以沒有 uv 工具可管理。"
            case .failed: return "uv 工具清單讀取失敗，請按「重新檢查」再試一次。"
            case .readyWithoutUpdateStatus: return "無法向 uv 查詢新版本（可能沒有網路），目前只列出已安裝的版本。"
            case .unknown, .ready: return nil
            }
        }
    }
    
    public var body: some View {
        PackageListPage(
            viewModel: viewModel,
            title: mode == .pip ? "Python" : "Python 工具",
            subtitle: subtitle,
            noun: mode == .pip ? "Python 套件" : "uv 工具",
            notice: notice,
            packages: mode == .pip ? viewModel.pythonPackages : viewModel.uvTools,
            outdatedCount: mode == .pip ? viewModel.outdatedPythonCount : viewModel.outdatedUVCount,
            extraFilter: { _ in true }
        ) {
            DKSegmented(options: [
                (Mode.pip, "pip 套件 \(viewModel.pythonPackages.count)"),
                (.uv, "uv 工具 \(viewModel.uvTools.count)")
            ], selection: $mode)
        }
    }
}

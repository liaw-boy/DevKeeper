import SwiftUI

public struct ConsoleView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "terminal")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text("執行歷程與即時日誌")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                        
                        Text("\(viewModel.consoleLogs.count) 行記錄")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    
                    Text("監控套件安裝、升級、安全修復與終端機 CLI 即時執行輸出")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if viewModel.isActionRunning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text(viewModel.actionStage.isEmpty ? "執行中..." : viewModel.actionStage)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 10)
                }
                
                Button(action: {
                    viewModel.consoleLogs.removeAll()
                    viewModel.liveLogOutput = ""
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                        Text("清除日誌")
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
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
            
            Divider()
                .background(Theme.subtleBorder)
            
            // Console output area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.consoleLogs.enumerated()), id: \.offset) { _, log in
                            Text(log)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        if !viewModel.liveLogOutput.isEmpty {
                            Text(viewModel.liveLogOutput)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.92))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(20)
                }
                .background(Color(red: 0.05, green: 0.06, blue: 0.07))
                .onChange(of: viewModel.liveLogOutput) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: viewModel.consoleLogs.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
        .background(Theme.canvasBackground)
    }
}

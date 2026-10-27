import DevKeeperCore
import SwiftUI

public struct ConsoleView: View {
    @ObservedObject var viewModel: AppViewModel
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    private var isEmpty: Bool { viewModel.consoleLogs.isEmpty && viewModel.liveLogOutput.isEmpty }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DKPageHeader(
                "執行日誌",
                subtitle: viewModel.isActionRunning
                    ? (viewModel.actionStage.isEmpty ? "執行中…" : viewModel.actionStage)
                    : "安裝、更新、修復與背景檢查的紀錄",
                count: viewModel.consoleLogs.isEmpty ? nil : "\(viewModel.consoleLogs.count) 行"
            ) {
                DKButton("複製", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        (viewModel.consoleLogs + (viewModel.liveLogOutput.isEmpty ? [] : [viewModel.liveLogOutput])).joined(separator: "\n"),
                        forType: .string
                    )
                }
                .disabled(isEmpty)
                DKButton("清除", systemImage: "trash") {
                    viewModel.consoleLogs.removeAll()
                    viewModel.liveLogOutput = ""
                }
                .disabled(isEmpty)
            }
            
            Group {
                if isEmpty {
                    DKEmptyState(kind: .empty, title: "還沒有紀錄", message: "執行安裝或更新後，輸出會顯示在這裡。")
                        .dkCard(padding: 0)
                } else {
                    output
                }
            }
            .padding(.horizontal, DK.pagePadding)
            .padding(.bottom, DK.pagePadding)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .background(DK.background)
    }
    
    private var output: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DK.Space.xs) {
                    ForEach(Array(viewModel.consoleLogs.enumerated()), id: \.offset) { _, log in
                        Text(log)
                            .font(DK.Font.mono)
                            .foregroundColor(DK.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if !viewModel.liveLogOutput.isEmpty {
                        Text(viewModel.liveLogOutput)
                            .font(DK.Font.mono)
                            .foregroundColor(DK.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .padding(DK.Space.l)
            }
            .background(
                RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous).fill(DK.surfaceSunken)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous).stroke(DK.border, lineWidth: 1)
            )
            .onChange(of: viewModel.liveLogOutput) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
            .onChange(of: viewModel.consoleLogs.count) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

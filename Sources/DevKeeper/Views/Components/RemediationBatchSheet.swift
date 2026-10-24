import DevKeeperCore
import SwiftUI

/// One confirmation for all alternative fixes proposed after a one-click fix.
struct RemediationBatchSheet: View {
    let batch: AppViewModel.RemediationBatch
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .foregroundColor(Theme.primaryIndigo)
                Text("這些套件無法直接升級，要改用下列做法嗎？")
                    .font(.system(size: 15, weight: .bold))
            }
            
            Text("直接升級已先嘗試過。下列做法會先把工具裝好，全部成功後才移除舊的；任何一步失敗都不會動舊環境。")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(batch.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: item.plan.kind == .migrate ? "arrow.triangle.branch" : "trash")
                                    .font(.system(size: 11))
                                    .foregroundColor(Theme.primaryIndigo)
                                Text(item.plan.kind == .migrate ? "搬到獨立環境" : "移除套件")
                                    .font(.system(size: 12, weight: .semibold))
                                Text("（為了修復 \(item.plan.packageName)）")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            ForEach(item.plan.summaryLines, id: \.self) { line in
                                Text("• \(line)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
            .frame(maxHeight: 320)
            
            HStack(spacing: 10) {
                Spacer()
                Button(action: onCancel) {
                    Text("取消")
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.bouncy)
                Button(action: onConfirm) {
                    Text("確認並修復")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Theme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.bouncy)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Theme.canvasBackground)
        .preferredColorScheme(.dark)
    }
}

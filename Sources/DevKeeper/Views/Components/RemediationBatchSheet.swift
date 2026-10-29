import DevKeeperCore
import SwiftUI

/// One confirmation for all alternative fixes proposed after a one-click fix.
struct RemediationBatchSheet: View {
    let batch: AppViewModel.RemediationBatch
    let onConfirm: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        DKModalPanel(
            "這些套件無法直接更新，要改用下列做法嗎？",
            subtitle: "直接更新已先嘗試過。下列做法會先把工具裝好，全部成功後才移除舊的；任何一步失敗都不會動舊環境。",
            width: 520
        ) {
            VStack(alignment: .leading, spacing: DK.Space.s) {
                ForEach(batch.items) { item in
                    VStack(alignment: .leading, spacing: DK.Space.xs) {
                        HStack(spacing: DK.Space.s) {
                            Image(systemName: item.plan.kind == .migrate ? "arrow.triangle.branch" : "trash")
                                .font(.system(size: DK.Icon.small))
                                .foregroundColor(DK.accent)
                            Text(item.plan.kind == .migrate ? "搬到獨立環境" : "移除套件")
                                .font(DK.Font.bodyMedium)
                                .foregroundColor(DK.textPrimary)
                            Text("為了修復 \(item.plan.packageName)")
                                .font(DK.Font.caption)
                                .foregroundColor(DK.textTertiary)
                        }
                        ForEach(item.plan.summaryLines, id: \.self) { line in
                            Text(line)
                                .font(DK.Font.caption)
                                .foregroundColor(DK.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(DK.Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous).fill(DK.surfaceSunken))
                }
            }
        } footer: {
            DKButton("取消", action: onCancel)
            DKButton("確認執行", kind: .primary, action: onConfirm)
        }
    }
}

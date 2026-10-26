import DevKeeperCore
import SwiftUI

/// One package in a list: source badge, name, versions, status and actions. Shared by every package page.
public struct PackageRow: View {
    public let package: PackageItem
    public let isActionRunning: Bool
    public let onUpgrade: () -> Void
    public let onCleanUninstall: () -> Void

    @State private var isHovered = false
    @State private var copiedCommand = false
    @EnvironmentObject private var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay

    private var isJustCompleted: Bool {
        viewModel.completedPackageId == package.id
    }

    public init(
        package: PackageItem,
        isActionRunning: Bool,
        onUpgrade: @escaping () -> Void,
        onCleanUninstall: @escaping () -> Void
    ) {
        self.package = package
        self.isActionRunning = isActionRunning
        self.onUpgrade = onUpgrade
        self.onCleanUninstall = onCleanUninstall
    }

    private var isBusyElsewhere: Bool {
        viewModel.isActionRunning && viewModel.currentActionPackageId != package.id
    }

    private var isThisRunning: Bool {
        viewModel.isActionRunning && viewModel.currentActionPackageId == package.id
    }

    public var body: some View {
        HStack(alignment: .center, spacing: DK.Space.m) {
            DKPackageAvatar(name: package.name, source: DKSource(package.type), size: 32)

            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                Text(package.name)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .dkTooltip(package.name)
                if let desc = package.description, !desc.isEmpty {
                    Text(desc)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .dkTooltip(desc)
                }
                if package.status.isOutdated, !package.upgradeCommand.isEmpty {
                    copyCommandButton
                }
            }
            .frame(minWidth: 160, alignment: .leading)

            Spacer(minLength: DK.Space.l)

            versions
                .frame(width: 170, alignment: .trailing)

            trailing
                .frame(width: 170, alignment: .trailing)

            if let url = InputValidator.httpsURL(package.homepage) {
                DKIconButton("link", help: "開啟專案頁面：\(url.host ?? url.absoluteString)", compact: true) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                // Keeps the columns aligned across rows with and without a link.
                Color.clear.frame(width: DK.compactControlHeight, height: DK.compactControlHeight)
            }
            
            DKIconButton("trash", help: "移除 \(package.name)", compact: true) {
                overlay?.confirm(
                    "移除 \(package.name)？",
                    message: "將執行以下指令。",
                    commands: package.uninstallCommands,
                    confirmTitle: "移除",
                    destructive: true,
                    onConfirm: onCleanUninstall
                )
            }
            .disabled(viewModel.isActionRunning || package.uninstallCommands.isEmpty)
        }
        .padding(.vertical, DK.Space.s)
        .padding(.horizontal, DK.Space.m)
        .background(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .fill(isHovered ? DK.surfaceHover : DK.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DK.Radius.card, style: .continuous)
                .stroke(isJustCompleted ? DK.success.opacity(0.6) : DK.border, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { overlay?.present { PackageDetailSheet(package: package, viewModel: viewModel) } }
        .onHover { isHovered = $0 }
    }

    private var copyCommandButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(package.upgradeCommand, forType: .string)
            copiedCommand = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { copiedCommand = false }
        } label: {
            HStack(spacing: DK.Space.xs) {
                Text("$ \(package.upgradeCommand)")
                    .font(DK.Font.mono)
                    .foregroundColor(DK.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: copiedCommand ? "checkmark" : "doc.on.doc")
                    .font(.system(size: DK.Icon.tiny))
                    .foregroundColor(copiedCommand ? DK.success : DK.textTertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DKPressStyle())
        .dkTooltip(copiedCommand ? "已複製" : "複製升級指令")
    }

    private var versions: some View {
        HStack(spacing: DK.Space.tight) {
            Text(package.currentVersion)
                .font(DK.Font.mono)
                .foregroundColor(DK.textSecondary)
                .lineLimit(1)
            if let latest = package.latestVersion, package.status.isOutdated {
                Image(systemName: "arrow.right")
                    .font(.system(size: DK.Icon.tiny, weight: .semibold))
                    .foregroundColor(DK.accent)
                Text(latest)
                    .font(DK.Font.mono)
                    .foregroundColor(DK.textPrimary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if isThisRunning && viewModel.currentActionIsUninstall {
            HStack(spacing: DK.Space.s) {
                DKSpinner(size: 12)
                Text("移除中…")
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
            }
        } else if isThisRunning || isJustCompleted {
            VStack(alignment: .trailing, spacing: DK.Space.xs) {
                if isJustCompleted {
                    Text("升級完成")
                        .font(DK.Font.caption)
                        .foregroundColor(DK.success)
                } else {
                    Text(viewModel.actionStage.isEmpty ? "升級中…" : viewModel.actionStage)
                        .font(DK.Font.caption)
                        .foregroundColor(DK.textSecondary)
                        .lineLimit(1)
                    DKProgressBar()
                        .frame(width: 120)
                }
            }
        } else {
            HStack(spacing: DK.Space.m) {
                DKStatusText(status: package.status)
                if package.status.isOutdated {
                    DKButton("升級", kind: .primary,
                             disabledReason: isBusyElsewhere ? "正在執行其他操作" : nil, action: onUpgrade)
                        .disabled(viewModel.isActionRunning || isActionRunning)
                }
            }
        }
    }
}

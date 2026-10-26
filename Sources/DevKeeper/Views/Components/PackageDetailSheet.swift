import DevKeeperCore
import SwiftUI

public struct PackageDetailSheet: View {
    public let package: PackageItem
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dkOverlay) private var overlay
    
    @State private var isFetchingDetails = false
    @State private var detailedNotes: String = ""
    @State private var notesTitle: String?
    @State private var notesURL: String?
    @State private var copiedCommandInSheet = false
    
    public init(package: PackageItem, viewModel: AppViewModel) {
        self.package = package
        self.viewModel = viewModel
    }
    
    public var body: some View {
        DKModalPanel(package.name, subtitle: package.type.displayName, width: 540) {
            VStack(alignment: .leading, spacing: DK.Space.l) {
                HStack(spacing: DK.Space.s) {
                    infoBox("目前版本") {
                        Text(package.currentVersion)
                            .font(DK.Font.mono)
                            .foregroundColor(DK.textPrimary)
                    }
                    infoBox("最新版本") {
                        Text(package.latestVersion ?? "檢查中…")
                            .font(DK.Font.mono)
                            .foregroundColor(package.status.isOutdated ? DK.accent : DK.textPrimary)
                    }
                    infoBox("狀態") {
                        DKStatusText(status: package.status)
                    }
                }
                
                block("說明") {
                    Text(package.description?.isEmpty == false ? package.description! : "沒有提供說明。")
                        .font(DK.Font.body)
                        .foregroundColor(DK.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                if package.status.isOutdated, !package.upgradeCommand.isEmpty {
                    block("升級指令") {
                        HStack(spacing: DK.Space.s) {
                            Text("$ \(package.upgradeCommand)")
                                .font(DK.Font.mono)
                                .foregroundColor(DK.textPrimary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Spacer(minLength: DK.Space.s)
                            DKButton(copiedCommandInSheet ? "已複製" : "複製",
                                     systemImage: copiedCommandInSheet ? "checkmark" : "doc.on.doc", kind: .ghost) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(package.upgradeCommand, forType: .string)
                                copiedCommandInSheet = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedCommandInSheet = false }
                            }
                        }
                    }
                }
                
                block("發布說明", trailing: isFetchingDetails ? AnyView(DKSpinner(size: 12)) : nil) {
                    VStack(alignment: .leading, spacing: DK.Space.tight) {
                        if !detailedNotes.isEmpty {
                            if let title = notesTitle {
                                Text(title)
                                    .font(DK.Font.bodyMedium)
                                    .foregroundColor(DK.textPrimary)
                            }
                            Text(detailedNotes)
                                .font(DK.Font.mono)
                                .foregroundColor(DK.textSecondary)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if let url = InputValidator.httpsURL(notesURL, allowedHosts: ["github.com"]) {
                                Link("在 GitHub 查看完整說明", destination: url)
                                    .font(DK.Font.caption)
                            }
                        } else {
                            Text(isFetchingDetails ? "正在取得發布說明…" : notesUnavailableMessage)
                                .font(DK.Font.caption)
                                .foregroundColor(DK.textSecondary)
                        }
                    }
                }
            }
        } footer: {
            if let url = InputValidator.httpsURL(package.homepage) {
                DKButton("官方網站", systemImage: "safari", kind: .ghost) { NSWorkspace.shared.open(url) }
            }
            if !package.uninstallCommands.isEmpty {
                DKButton("移除", systemImage: "trash", kind: .danger, disabledReason: viewModel.isActionRunning ? "正在執行其他操作" : nil) {
                    overlay?.confirm(
                        "移除 \(package.name)？",
                        message: "將執行以下指令。",
                        commands: package.uninstallCommands,
                        confirmTitle: "移除",
                        destructive: true
                    ) {
                        Task { await viewModel.cleanUninstall(package: package) }
                    }
                }
                .disabled(viewModel.isActionRunning)
            }
            DKButton("關閉") { overlay?.dismissModal() }
            if package.status.isOutdated {
                DKButton("升級", kind: .primary, disabledReason: viewModel.isActionRunning ? "正在執行其他操作" : nil) {
                    overlay?.dismissModal()
                    Task { await viewModel.upgradeSingle(package: package) }
                }
                .disabled(viewModel.isActionRunning)
            }
        }
        .task { await loadReleaseNotes() }
    }
    
    private func infoBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.xs) {
            Text(title)
                .font(DK.Font.caption)
                .foregroundColor(DK.textTertiary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DK.Space.m)
        .background(RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous).fill(DK.surfaceSunken))
    }
    
    private func block<Content: View>(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.s) {
            HStack {
                Text(title)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                Spacer()
                trailing
            }
            content()
                .padding(DK.Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous).fill(DK.surfaceSunken))
        }
    }
    
    private var notesVersion: String {
        package.status.isOutdated ? (package.latestVersion ?? package.currentVersion) : package.currentVersion
    }
    
    private var notesUnavailableMessage: String {
        GitHubReleaseService.githubRepo(from: package.homepage) == nil
            ? "此套件的官網不是 GitHub，無法自動取得發布說明，請至官方網站查看。"
            : "在 GitHub 上找不到 \(notesVersion) 版本對應的發布說明。"
    }
    
    private func loadReleaseNotes() async {
        guard let repo = GitHubReleaseService.githubRepo(from: package.homepage) else { return }
        isFetchingDetails = true
        defer { isFetchingDetails = false }
        guard let release = await GitHubReleaseService.shared.fetchReleaseNotes(owner: repo.owner, repo: repo.repo, version: notesVersion),
              let body = release.body?.trimmingCharacters(in: .whitespacesAndNewlines), !body.isEmpty else { return }
        let limit = 3000
        detailedNotes = body.count > limit ? String(body.prefix(limit)) + "\n…" : body
        notesTitle = release.name?.isEmpty == false ? release.name : release.tagName
        notesURL = release.htmlUrl
    }
}

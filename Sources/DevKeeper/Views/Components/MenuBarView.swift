import SwiftUI
import AppKit

/// Menu bar popover. Uses the same tokens and shapes as the main window
/// (Theme colors, tinted icon tiles, card surfaces, gradient primary button).
public struct MenuBarView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var showMore = false

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }

    private var allOutdatedItems: [PackageItem] {
        (viewModel.npmPackages + viewModel.brewPackages + viewModel.pythonPackages).filter { $0.status.isOutdated }
    }

    /// Only npm and Homebrew are upgraded by the "upgrade all" action.
    private var upgradableCount: Int {
        viewModel.outdatedNpmCount + viewModel.outdatedBrewCount
    }

    public var body: some View {
        VStack(spacing: 10) {
            header
            summaryBanner
            categoryCards
            if !allOutdatedItems.isEmpty {
                previewCard
            }
            securityBanner
            footer
        }
        .padding(14)
        .frame(width: 380)
        .background(Theme.canvasBackground)
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.primaryGradient)
                    .frame(width: 28, height: 28)
                    .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 4, x: 0, y: 1.5)
                Image(systemName: "cube.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("DevKeeper")
                        .font(.system(size: 14, weight: .bold))
                    Text("v\(AppViewModel.appVersion)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.05))
                        .clipShape(Capsule())
                }
                HStack(spacing: 5) {
                    if viewModel.isScanning || viewModel.isActionRunning {
                        ProgressView().controlSize(.mini)
                        Text(viewModel.isActionRunning ? "正在執行操作..." : "正在同步狀態...")
                    } else {
                        Circle().fill(Theme.successGreen).frame(width: 6, height: 6)
                        Text(lastScanText)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }

            Spacer()

            squareButton("arrow.clockwise", help: "立即重新掃描") {
                Task { await viewModel.scanAll() }
            }
            .disabled(viewModel.isScanning || viewModel.isActionRunning)

            squareButton("macwindow", help: "開啟 DevKeeper 主視窗") {
                openMainWindow()
            }
        }
    }

    private var lastScanText: String {
        if let date = viewModel.lastScanDate {
            return "上次檢查 \(Self.timeFormatter.string(from: date))"
        }
        return "就緒 (即時監聽)"
    }

    // MARK: - Summary

    private var summaryBanner: some View {
        let count = viewModel.totalOutdatedCount
        let tint = count > 0 ? Theme.warningAmber : Theme.successGreen
        return HStack(spacing: 10) {
            tile(count > 0 ? "bolt.fill" : "checkmark", tint: tint, size: 30)

            if count > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(count)")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(tint)
                    Text("項可升級")
                        .font(.system(size: 13, weight: .semibold))
                }
            } else {
                Text("所有項目均為最新")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Categories

    private var categoryCards: some View {
        VStack(spacing: 6) {
            categoryCard("AI 開發工具", "sparkles", Theme.primaryIndigo, viewModel.aiTools.count, viewModel.outdatedAIToolCount, .aiTools)
            categoryCard("Homebrew", "shippingbox", Theme.warningAmber, viewModel.brewPackages.count, viewModel.outdatedBrewCount, .brew)
            categoryCard("Python (pip)", "chevron.left.forwardslash.chevron.right", Theme.successGreen, viewModel.pythonPackages.count, viewModel.outdatedPythonCount, .python)
            categoryCard("npm 全域工具", "cube", Theme.infoCyan, viewModel.npmPackages.count, viewModel.outdatedNpmCount, .npm)
        }
    }

    private func categoryCard(_ title: String, _ symbol: String, _ tint: Color, _ count: Int, _ outdated: Int, _ tab: NavigationTab) -> some View {
        Button {
            openTab(tab)
        } label: {
            HStack(spacing: 10) {
                tile(symbol, tint: tint, size: 26)

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Text("\(count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.secondary)

                Spacer(minLength: 4)

                if outdated > 0 {
                    Text("\(outdated) 待更")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(Theme.warningAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.warningAmber.opacity(0.14))
                        .clipShape(Capsule())
                } else {
                    Text("最新")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.successGreen)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(.bouncy(scale: 0.98))
    }

    // MARK: - Preview

    private var previewCard: some View {
        let items = Array(allOutdatedItems.prefix(4))
        return VStack(spacing: 0) {
            ForEach(items) { item in
                HStack(spacing: 8) {
                    Image(systemName: item.type.sfSymbol)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(Theme.warningAmber)
                        .frame(width: 14)
                    Text(item.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 5) {
                        Text(item.currentVersion)
                            .foregroundColor(.secondary)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        Text(item.latestVersion ?? "")
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 10.5, design: .monospaced))
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)

                if item.id != items.last?.id {
                    Divider().background(Theme.subtleBorder)
                }
            }

            if allOutdatedItems.count > 4 {
                Divider().background(Theme.subtleBorder)
                Button {
                    openMainWindow()
                } label: {
                    Text("還有 \(allOutdatedItems.count - 4) 項，於主視窗查看")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .cardSurface()
    }

    // MARK: - Security

    private var securityBanner: some View {
        let count = viewModel.vulnerabilityCount
        let tint = count > 0 ? Theme.dangerRed : Theme.successGreen
        return Button {
            if count > 0 { openTab(.security) } else { openMainWindow() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: count > 0 ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 16))
                    .foregroundColor(tint)
                Text(count > 0 ? "偵測到 \(count) 個安全性弱點 (CVE)" : "本機無已知安全性弱點")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)
                    .monospacedDigit()
                Spacer()
                Text(count > 0 ? "查看" : "總覽")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(tint)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(tint.opacity(count > 0 ? 0.10 : 0.06))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tint.opacity(count > 0 ? 0.35 : 0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bouncy(scale: 0.98))
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 8) {
            if showMore {
                VStack(spacing: 0) {
                    moreRow("gearshape", "設定") { openTab(.settings) }
                    Divider().background(Theme.subtleBorder)
                    moreRow("shield.checkered", "安全稽核") { openTab(.security) }
                    Divider().background(Theme.subtleBorder)
                    moreRow("power", "結束 DevKeeper") { NSApplication.shared.terminate(nil) }
                }
                .cardSurface()
                .transition(.opacity)
            }

            HStack(spacing: 8) {
                if upgradableCount > 0 {
                    Button {
                        Task {
                            await viewModel.upgradeAllOutdatedNpm()
                            await viewModel.upgradeAllOutdatedBrew()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11.5, weight: .bold))
                            Text("全部升級 (\(upgradableCount))")
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .background(Theme.primaryGradient)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .shadow(color: Theme.primaryIndigo.opacity(0.4), radius: 6, x: 0, y: 2)
                    }
                    .buttonStyle(.bouncy)
                    .disabled(viewModel.isActionRunning || viewModel.isScanning)
                    .help("升級 npm 與 Homebrew 的待升級項目")
                }

                Spacer()

                squareButton(showMore ? "chevron.down" : "ellipsis", help: "更多") {
                    withAnimation(.easeOut(duration: 0.15)) { showMore.toggle() }
                }
            }
        }
    }

    private func moreRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        MoreRow(icon: icon, title: title, action: action)
    }

    // MARK: - Shared pieces

    private func tile(_ symbol: String, tint: Color, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .medium))
                .foregroundColor(tint)
        }
    }

    private func squareButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundColor(.primary)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        }
        .buttonStyle(.bouncy)
        .help(help)
    }

    private func openMainWindow() {
        StatusBarController.shared?.closePopover()
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func openTab(_ tab: NavigationTab) {
        viewModel.selectedTab = tab
        openMainWindow()
    }
}

private extension View {
    /// Same surface as the main window's metric cards.
    func cardSurface() -> some View {
        self.background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Theme.subtleBorder, lineWidth: 1)
                )
        )
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .frame(width: 18)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(hovering ? Color.white.opacity(0.06) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

import DevKeeperCore
import SwiftUI

/// Every design-system component in light and dark, side by side. Open it by launching the app with
/// `DEVKEEPER_GALLERY=1`; it is not reachable from the normal UI.
struct DesignGalleryView: View {
    var body: some View {
        // Each column has its own overlay host so floating panels use that column's appearance.
        HStack(spacing: 0) {
            DKOverlayHost { GalleryColumn(title: "淺色") }.environment(\.colorScheme, .light)
            DKOverlayHost { GalleryColumn(title: "深色") }.environment(\.colorScheme, .dark)
        }
        .frame(minWidth: 1100, minHeight: 820)
    }
}

private struct GalleryColumn: View {
    let title: String
    @State private var search = ""
    @State private var filter = 0
    @State private var sort = "name"
    @State private var toggleA = true
    @State private var toggleB = false
    @Environment(\.dkOverlay) private var overlay
    @State private var sortFrame: CGRect = .zero
    @State private var iconFrame: CGRect = .zero
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DK.Space.xl) {
                DKPageHeader("npm 套件", subtitle: "全域安裝的 npm 套件與可更新的版本", count: "42 個") {
                    DKButton("檢查") {}
                    DKButton("全部更新", kind: .primary) {}
                }
                .padding(.horizontal, -DK.pagePadding)
                
                group("按鈕") {
                    HStack(spacing: DK.Space.s) {
                        DKButton("更新", kind: .primary) {}
                        DKButton("檢查") {}
                        DKButton("移除", kind: .danger) {}
                        DKButton("取消", kind: .ghost) {}
                    }
                    HStack(spacing: DK.Space.s) {
                        DKButton("更新中", kind: .primary, isLoading: true) {}
                        DKButton("檢查", disabledReason: "正在執行其他操作") {}.disabled(true)
                        DKIconButton("arrow.clockwise", help: "重新檢查") {}
                            .dkTrackFrame($iconFrame)
                        DKActionMenu(help: "更多操作", items: [
                            .init(title: "選擇專案資料夾…") {},
                            .init(title: "移除", destructive: true) {}
                        ])
                    }
                }
                
                group("輸入與選擇") {
                    HStack(spacing: DK.Space.s) {
                        DKSearchField(placeholder: "搜尋套件", text: $search)
                        DKSegmented(options: [(0, "全部"), (1, "可更新")], selection: $filter)
                        DKDropdown(options: [("name", "名稱"), ("scope", "更新幅度")], selection: $sort, label: "排序")
                            .dkTrackFrame($sortFrame)
                    }
                    HStack(spacing: DK.Space.l) {
                        DKSwitch(isOn: $toggleA)
                        DKSwitch(isOn: $toggleB)
                        DKSpinner()
                        DKProgressBar(value: 0.4).frame(width: 120)
                        DKProgressBar().frame(width: 120)
                    }
                }
                
                group("狀態與標籤") {
                    HStack(spacing: DK.Space.l) {
                        DKStatusText(status: .upToDate)
                        DKStatusText(status: .minor)
                        DKStatusText(status: .major)
                        DKStatusText(status: .error)
                    }
                    HStack(spacing: DK.Space.s) {
                        DKTag("npm")
                        DKTag("uv tool：demo-tool")
                        DKTag("高", tone: .warning)
                        DKTag("嚴重", tone: .danger)
                    }
                }
                
                group("強調與數據") {
                    HStack(spacing: DK.Space.s) {
                        DKSourceBadge(.npm)
                        DKSourceBadge(.python)
                        DKSourceBadge(.homebrew)
                        DKSourceBadge(.cask)
                        DKSourceBadge(.ai)
                        DKSourceBadge(.database)
                        DKIconTile("shield")
                        DKButton("檢查", systemImage: "arrow.clockwise") {}
                        DKButton("更新", systemImage: "arrow.up.circle", kind: .primary) {}
                    }
                    HStack(spacing: DK.Space.s) {
                        DKPackageAvatar(name: "openssl@4", source: .homebrew)
                        DKPackageAvatar(name: "postgresql", source: .database)
                        DKPackageAvatar(name: "ffmpeg", source: .homebrew)
                        DKPackageAvatar(name: "eslint", source: .npm)
                        DKPackageAvatar(name: "requests", source: .python)
                        DKPackageAvatar(name: "unknown-tool", source: .cask)
                    }
                    HStack(alignment: .top, spacing: DK.Space.s) {
                        DKMetricCard(title: "可更新", value: "12", caption: "共 42 個套件", systemImage: "arrow.up.circle", barValue: 12.0 / 42)
                        DKMetricCard(title: "npm", value: "5", source: .npm, barValue: 0.25)
                        DKMetricCard(title: "安全弱點", value: "3", systemImage: "shield", valueColor: DK.danger)
                    }
                    DKSegmentBar(segments: [(1, DK.danger), (2, DK.warning), (4, DK.textTertiary)])
                    DKBar(value: 0.3)
                }
                
                group("卡片與清單") {
                    VStack(alignment: .leading, spacing: 0) {
                        sampleRow("typescript", "5.6.2", "5.6.3", .patch)
                        DKDivider()
                        sampleRow("@anthropic-ai/claude-code", "2.1.300", "2.1.310", .minor)
                        DKDivider()
                        sampleRow("eslint", "8.57.0", "9.12.0", .major)
                    }
                    .dkCard(padding: 0)
                    DKCommandBlock(command: "npm install -g typescript@5.6.3")
                    VStack(spacing: 0) {
                        DKSettingRow("登入時啟動", detail: "登入系統時自動啟動 DevKeeper") {
                            DKSwitch(isOn: $toggleB)
                        }
                        DKDivider()
                        DKSettingRow("檢查頻率") {
                            DKDropdown(options: [(30, "每 30 分鐘"), (60, "每小時")], selection: .constant(30))
                        }
                    }
                    .padding(.horizontal, DK.Space.l)
                    .dkCard(padding: 0)
                }
                
                group("狀態頁與確認") {
                    DKEmptyState(kind: .allCurrent, title: "全部都是最新版本", message: "沒有需要更新的 npm 套件。")
                        .dkCard(padding: 0)
                    DKButton("開啟確認面板") {
                        overlay?.confirm("移除 typescript？", message: "只會執行 npm uninstall，不會刪除專案內的設定檔。",
                                         commands: ["npm uninstall -g typescript"], confirmTitle: "移除", destructive: true) {}
                    }
                }
            }
            .padding(DK.pagePadding)
        }
        .background(DK.background)
        .task { await showRequestedOverlay() }
        .overlay(alignment: .topTrailing) {
            Text(title).font(DK.Font.micro).foregroundColor(DK.textTertiary).padding(DK.Space.s)
        }
    }
    
    /// `DEVKEEPER_GALLERY_SHOW=dropdown|tooltip|longtip|confirm|longmodal|modaldropdown` opens that floating
    /// element on launch for screenshots.
    private func showRequestedOverlay() async {
        guard let what = ProcessInfo.processInfo.environment["DEVKEEPER_GALLERY_SHOW"] else { return }
        try? await Task.sleep(nanoseconds: 800_000_000)
        switch what {
        case "dropdown":
            overlay?.showPanel(anchor: sortFrame, width: max(sortFrame.width, 160)) {
                DKDropdownPanel(options: [("name", "名稱"), ("scope", "更新幅度"), ("type", "類型")], selection: $sort)
            }
        case "tooltip":
            overlay?.showTip("重新檢查所有 npm 套件的最新版本", anchor: iconFrame)
        case "longtip":
            overlay?.showTip("這是一段很長的提示文字，用來確認提示框最寬只到 320 點並且會自動換行，而不是撐開整個視窗或跑出畫面之外。" +
                             "第二句話讓內容超過兩行，檢查行數限制與位置是否都在視窗內。", anchor: iconFrame)
        case "longmodal":
            overlay?.confirm("更新 30 個套件？", message: "以下指令會依序執行。",
                             commands: (1...30).map { "npm install -g example-package-\($0)@1.2.\($0)" }, confirmTitle: "全部更新") {}
        case "modaldropdown":
            overlay?.present { GalleryModalWithDropdown() }
        case "confirm":
            overlay?.confirm("移除 typescript？", message: "只會執行 npm uninstall，不會刪除專案內的設定檔。",
                             commands: ["npm uninstall -g typescript"], confirmTitle: "移除", destructive: true) {}
        default:
            break
        }
    }
    
    private func group<Content: View>(_ name: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.m) {
            DKSectionTitle(name)
            content()
        }
    }
    
    private func sampleRow(_ name: String, _ current: String, _ latest: String, _ status: UpdateStatus) -> some View {
        HStack(spacing: DK.Space.m) {
            Text(name).font(DK.Font.bodyMedium).foregroundColor(DK.textPrimary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(current).font(DK.Font.mono).foregroundColor(DK.textSecondary).frame(width: 90, alignment: .leading)
            Text(latest).font(DK.Font.mono).foregroundColor(DK.textPrimary).frame(width: 90, alignment: .leading)
            DKStatusText(status: status).frame(width: 64, alignment: .leading)
            DKButton("更新") {}
        }
        .padding(.horizontal, DK.Space.l)
        .padding(.vertical, DK.Space.s)
    }
}

/// A modal that contains a dropdown, to check that floating panels open above modal panels.
private struct GalleryModalWithDropdown: View {
    @State private var choice = 30
    @Environment(\.dkOverlay) private var overlay
    @State private var frame: CGRect = .zero
    
    var body: some View {
        DKModalPanel("偏好設定") {
            DKSettingRow("檢查頻率") {
                DKDropdown(options: [(15, "每 15 分鐘"), (30, "每 30 分鐘"), (60, "每小時")], selection: $choice)
                    .dkTrackFrame($frame)
            }
        } footer: {
            DKButton("關閉") { overlay?.dismissModal() }
        }
        .task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            overlay?.showPanel(anchor: frame, width: max(frame.width, 160)) {
                DKDropdownPanel(options: [(15, "每 15 分鐘"), (30, "每 30 分鐘"), (60, "每小時")], selection: $choice)
            }
        }
    }
}

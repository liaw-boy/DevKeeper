import DevKeeperCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    // Stored Preferences
    @AppStorage(DKAppearance.storageKey) private var appearanceRaw: String = DKAppearance.system.rawValue
    @AppStorage("scanIntervalMinutes") private var scanIntervalMinutes: Int = 30
    @AppStorage("enableFSEvents") private var enableFSEvents: Bool = true
    @AppStorage("checkSelfUpdate") private var checkSelfUpdate: Bool = true
    @AppStorage("enableSecurityAudit") private var enableSecurityAudit: Bool = true
    @AppStorage(StatusBarController.showStatusItemKey) private var showStatusBarItem: Bool = true
    @AppStorage("projectsRootPath") private var projectsRootPath: String = ""
    
    @State private var launchAtLogin: Bool = false
    @State private var launchAtLoginError: String?
    
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                    launchAtLoginError = nil
                } catch {
                    launchAtLoginError = "無法變更開機啟動：\(error.localizedDescription)（需從 DevKeeper.app 執行）"
                }
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        )
    }
    
    
    public init(viewModel: AppViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                DKPageHeader("設定", subtitle: "背景檢查、安全稽核與系統整合") {}
                VStack(alignment: .leading, spacing: DK.Space.xl) {
                    section("外觀") {
                        row(title: "主題", subtitle: "跟隨系統會隨 macOS 的淺色或深色切換") {
                            DKSegmented(
                                options: DKAppearance.allCases.map { ($0.rawValue, $0.title) },
                                selection: $appearanceRaw
                            )
                        }
                    }
                    
                    section("背景檢查") {
                        row(title: "檢查頻率", subtitle: "定時向 npm、PyPI 與 Homebrew 查詢最新版本") {
                            DKDropdown(options: [
                                (15, "每 15 分鐘"), (30, "每 30 分鐘"), (60, "每 1 小時"), (360, "每 6 小時")
                            ], selection: $scanIntervalMinutes)
                            .frame(width: 150, alignment: .trailing)
                        }
                        DKDivider()
                        toggleRow(
                            title: "監聽安裝目錄變更",
                            subtitle: "監看 Applications、Homebrew 與全域 node_modules，變更後約 2 秒自動重新整理",
                            isOn: $enableFSEvents
                        )
                        DKDivider()
                        toggleRow(
                            title: "檢查 DevKeeper 更新",
                            subtitle: "GitHub 有新版本時在介面提示，不會自動安裝",
                            isOn: $checkSelfUpdate
                        )
                    }
                    
                    section("安全稽核") {
                        toggleRow(
                            title: "用 Google OSV 比對已知弱點",
                            subtitle: "檢查已安裝的 npm 與 Python 套件是否有公開的弱點紀錄（CVE、GHSA）",
                            isOn: $enableSecurityAudit
                        )
                        .onChange(of: enableSecurityAudit) { _, enabled in
                            // Results from before the switch was turned off would otherwise stay on screen as current.
                            if !enabled { viewModel.clearSecurityResults() }
                        }
                        DKDivider()
                        row(
                            title: "本機專案資料夾",
                            subtitle: projectsRootPath.isEmpty ? "尚未設定，不會掃描本機專案" : projectsRootPath
                        ) {
                            HStack(spacing: DK.Space.s) {
                                if !projectsRootPath.isEmpty {
                                    DKButton("清除", kind: .ghost) { projectsRootPath = "" }
                                }
                                DKButton("選擇資料夾", systemImage: "folder") { chooseProjectsFolder() }
                            }
                        }
                    }
                    
                    section("系統") {
                        toggleRow(
                            title: "在選單列顯示",
                            subtitle: "顯示圖示與待升級數量；關閉後仍可從 Dock 開啟主視窗",
                            isOn: $showStatusBarItem
                        )
                        DKDivider()
                        toggleRow(
                            title: "登入時自動啟動",
                            subtitle: "登入 macOS 後自動啟動 DevKeeper",
                            isOn: launchAtLoginBinding
                        )
                        if let launchAtLoginError {
                            Text(launchAtLoginError)
                                .font(DK.Font.caption)
                                .foregroundColor(DK.danger)
                        }
                    }
                    
                    section("關於") {
                        HStack(spacing: DK.Space.m) {
                            Image(systemName: "shippingbox.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(DK.onAccent)
                                .frame(width: 36, height: 36)
                                .background(RoundedRectangle(cornerRadius: DK.Radius.control, style: .continuous).fill(DK.accent))
                            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                                Text("DevKeeper")
                                    .font(DK.Font.heading)
                                    .foregroundColor(DK.textPrimary)
                                Text("版本 \(AppViewModel.appVersion)（Build \(AppViewModel.appBuild)）")
                                    .font(DK.Font.caption)
                                    .foregroundColor(DK.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, DK.pagePadding)
                .padding(.bottom, DK.pagePadding)
            }
        }
        .background(DK.background)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .onChange(of: scanIntervalMinutes) { viewModel.restartBackgroundTimer() }
        .onChange(of: enableFSEvents) { viewModel.applyFileWatcherSetting() }
    }
    
    private func chooseProjectsFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            projectsRootPath = url.path
        }
    }
    
    // MARK: - Layout helpers
    
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DK.Space.m) {
            DKSectionTitle(title)
            VStack(alignment: .leading, spacing: DK.Space.m) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dkCard()
        }
    }
    
    private func row<Control: View>(title: String, subtitle: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: DK.Space.l) {
            VStack(alignment: .leading, spacing: DK.Space.xxs) {
                Text(title)
                    .font(DK.Font.bodyMedium)
                    .foregroundColor(DK.textPrimary)
                Text(subtitle)
                    .font(DK.Font.caption)
                    .foregroundColor(DK.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: DK.Space.l)
            control()
        }
    }
    
    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        row(title: title, subtitle: subtitle) {
            DKSwitch(isOn: isOn)
        }
    }
}

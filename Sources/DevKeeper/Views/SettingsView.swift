import DevKeeperCore
import ServiceManagement
import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    // Stored Preferences
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
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(Theme.primaryIndigo)
                        
                        Text("偏好設定")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.primary)
                    }
                    
                    Text("自訂 DevKeeper 之背景掃描排程、安全稽核頻率與系統整合")
                        .font(.system(size: 11.5))
                        .foregroundColor(.secondary)
                }
                
                Divider()
                    .background(Theme.subtleBorder)
                
                // Section 1: 背景排程與自動同步
                settingsCard(title: "背景掃描與自動同步", icon: "clock.arrow.2.circlepath") {
                    VStack(spacing: 14) {
                        // Row 1: 掃描頻率 Picker
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("定時背景掃描頻率")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(.primary)
                                Text("背景自動向 npm、PyPI 及 Homebrew 查詢最新版本資訊")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer(minLength: 16)
                            
                            Picker("", selection: $scanIntervalMinutes) {
                                Text("每 15 分鐘").tag(15)
                                Text("每 30 分鐘 (建議)").tag(30)
                                Text("每 1 小時").tag(60)
                                Text("每 6 小時").tag(360)
                            }
                            .frame(width: 170)
                        }
                        
                        Divider().background(Color.white.opacity(0.04))
                        
                        // Row 2: FSEvents Toggle
                        settingToggleRow(
                            title: "安裝目錄變更監聽",
                            subtitle: "監聽 Applications、Homebrew 與全域 node_modules，偵測到變更後約 2 秒自動重新整理",
                            isOn: $enableFSEvents
                        )
                        
                        Divider().background(Color.white.opacity(0.04))
                        
                        // Row 3: DevKeeper Self-Update Toggle
                        settingToggleRow(
                            title: "自動檢查 DevKeeper 本身更新",
                            subtitle: "當 GitHub Releases 有新版本時在介面發布通知",
                            isOn: $checkSelfUpdate
                        )
                    }
                }
                
                // Section 2: 安全性與弱點稽核 (OSV)
                settingsCard(title: "安全性與弱點稽核", icon: "shield.checkered") {
                    settingToggleRow(
                        title: "Google OSV 國際開源漏洞庫即時比對",
                        subtitle: "自動偵測已安裝之 npm 與 Python 套件是否存在已知 CVE / GHSA 漏洞",
                        isOn: $enableSecurityAudit
                    )
                }
                
                // Section 4: 系統與常駐
                settingsCard(title: "系統與開機啟動", icon: "macwindow") {
                    settingToggleRow(
                        title: "在選單列顯示 DevKeeper",
                        subtitle: "於頂部選單列顯示圖示與待更新數量；關閉後仍可從 Dock 開啟主視窗",
                        isOn: $showStatusBarItem
                    )
                    
                    Divider()
                        .background(Theme.subtleBorder)
                    
                    settingToggleRow(
                        title: "開機自動啟動常駐",
                        subtitle: "登入系統時自動啟動 DevKeeper",
                        isOn: launchAtLoginBinding
                    )
                    
                    if let launchAtLoginError {
                        Text(launchAtLoginError)
                            .font(.system(size: 11))
                            .foregroundColor(Theme.warningAmber)
                    }
                }
                
                // 本機專案資料夾（供安全稽核掃描專案相依套件使用）
                settingsCard(title: "本機專案資料夾", icon: "folder") {
                    HStack(spacing: 10) {
                        Text(projectsRootPath.isEmpty ? "尚未設定（不掃描本機專案）" : projectsRootPath)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        if !projectsRootPath.isEmpty {
                            Button("清除") { projectsRootPath = "" }
                        }
                        Button("選擇...") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                projectsRootPath = url.path
                            }
                        }
                    }
                }
                
                // Section 5: 關於 DevKeeper
                settingsCard(title: "關於 DevKeeper", icon: "info.circle") {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Theme.primaryGradient)
                                .frame(width: 44, height: 44)
                                .shadow(color: Theme.primaryIndigo.opacity(0.35), radius: 6, x: 0, y: 2)
                            Image(systemName: "cube.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DevKeeper for macOS")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.primary)
                            Text("版本 \(AppViewModel.appVersion) (Build \(AppViewModel.appBuild)) • 原生 Swift + SwiftUI")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                            Text("整合 Homebrew、npm、Python 與 Google OSV 安全稽核")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary.opacity(0.8))
                        }
                        
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.canvasBackground)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
        .onChange(of: scanIntervalMinutes) { viewModel.restartBackgroundTimer() }
        .onChange(of: enableFSEvents) { viewModel.applyFileWatcherSetting() }
    }
    
    // MARK: - Reusable Full-Width Settings Card
    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.primaryIndigo)
                Text(title)
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundColor(.primary)
            }
            
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading) // Enforce 100% full width on every card
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.subtleBorder, lineWidth: 1)
        )
    }
    
    // MARK: - Reusable Precision-Aligned Toggle Row
    private func settingToggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }
            
            Spacer(minLength: 16)
            
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }
    

}

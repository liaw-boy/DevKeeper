import SwiftUI

public struct SettingsView: View {
    @ObservedObject var viewModel: AppViewModel
    
    // Stored Preferences
    @AppStorage("scanIntervalMinutes") private var scanIntervalMinutes: Int = 30
    @AppStorage("enableFSEvents") private var enableFSEvents: Bool = true
    @AppStorage("checkSelfUpdate") private var checkSelfUpdate: Bool = true
    @AppStorage("enableSecurityAudit") private var enableSecurityAudit: Bool = true
    @AppStorage("launchAtLogin") private var launchAtLogin: Bool = true
    @AppStorage("gitHubToken") private var gitHubToken: String = ""
    @AppStorage("projectsRootPath") private var projectsRootPath: String = ""
    
    @State private var tokenTestStatus: String? = nil
    @State private var isTestingToken: Bool = false
    
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
                            title: "FSEvents 即時檔案目錄監聽",
                            subtitle: "監聽 /opt/homebrew 與 node_modules，終端機指令變更時毫秒級自動更新狀態",
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
                
                // Section 3: GitHub API 授權與私人儲存庫存取
                settingsCard(title: "GitHub API 授權與私人儲存庫", icon: "key.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("GitHub Personal Access Token (選填)")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.primary)
                            Text("1. 私人儲存庫存取：若您追蹤的 App 發布在私人 Repo，需提供具備 repo 讀取權限之 Token\n2. 頻率額度擴充：未填時訪客上限 60 次/小時（易超額）；填入後大幅提升至 5,000 次/小時")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                        }
                        
                        HStack(spacing: 10) {
                            SecureField("ghp_xxxxxxxxxxxx 或 github_pat_xxxxxxxxxxxx", text: $gitHubToken)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12, design: .monospaced))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(Theme.subtleBorder, lineWidth: 1)
                                )
                                .frame(maxWidth: .infinity)
                            
                            Button(action: {
                                testGitHubToken()
                            }) {
                                HStack(spacing: 4) {
                                    if isTestingToken {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                            .font(.system(size: 11))
                                        Text("驗證 Token")
                                            .font(.system(size: 11.5, weight: .semibold))
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .background(Color.white.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            }
                            .buttonStyle(.bouncy)
                            .disabled(gitHubToken.trimmingCharacters(in: .whitespaces).isEmpty || isTestingToken)
                        }
                        
                        if let status = tokenTestStatus {
                            Text(status)
                                .font(.system(size: 11.5))
                                .foregroundColor(status.contains("成功") ? Theme.successGreen : Theme.dangerRed)
                        }
                        
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11.5))
                                .foregroundColor(Color.secondary)
                            Text("提示：若追蹤的 GitHub App 或 CLI 工具皆為公開 (Public) 儲存庫，保持留空亦可正常運作。")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 2)
                    }
                }
                
                // Section 4: 系統與常駐
                settingsCard(title: "系統與開機啟動", icon: "macwindow") {
                    settingToggleRow(
                        title: "開機自動啟動常駐",
                        subtitle: "登入系統時自動於頂部選單列啟動 DevKeeper 守護開發環境",
                        isOn: $launchAtLogin
                    )
                }
                
                // 本機專案資料夾（供安全稽核與 GitHub 應用程式偵測使用）
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
                            Text("版本 \(AppViewModel.appVersion) (Build \(AppViewModel.appBuild)) • 原生 Swift 6.4 + SwiftUI")
                                .font(.system(size: 11.5))
                                .foregroundColor(.secondary)
                            Text("整合 Homebrew、npm、Python、GitHub Releases 與 Google OSV 安全稽核")
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
    
    private func testGitHubToken() {
        isTestingToken = true
        tokenTestStatus = nil
        
        Task {
            guard let url = URL(string: "https://api.github.com/user") else {
                isTestingToken = false
                return
            }
            var request = URLRequest(url: url)
            let trimmedToken = gitHubToken.trimmingCharacters(in: .whitespaces)
            request.setValue("Bearer \(trimmedToken)", forHTTPHeaderField: "Authorization")
            request.setValue("DevKeeper-MacApp", forHTTPHeaderField: "User-Agent")
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let login = json["login"] as? String {
                    tokenTestStatus = "驗證成功！已成功連結至 GitHub 帳號: @\(login)，API 頻率額度已擴充至 5,000 次/小時。"
                } else {
                    tokenTestStatus = "驗證失敗，請確認 Token 是否具有足夠權限或輸入是否正確。"
                }
            } catch {
                tokenTestStatus = "網路請求失敗: \(error.localizedDescription)"
            }
            isTestingToken = false
        }
    }
}

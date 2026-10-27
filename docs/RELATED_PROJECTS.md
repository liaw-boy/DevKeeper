# 相關專案整理

星數於 2026-10-26 以 GitHub API 查得；功能說明來自各倉庫的簡介或 README，未實際安裝操作（除非另註）。
AI 用量追蹤類（CodexBar、codeburn、headroom-desktop 等）DevKeeper 已有自己的實作，不列入比較。

## 1. 直接對手：管理多種套件管理器的圖形介面

| 星數 | 專案 | 重點 | 備註 |
|---|---|---|---|
| 26,760 | [Devolutions/UniGetUI](https://github.com/Devolutions/UniGetUI) | 一個介面管 WinGet、Scoop、npm、pip、cargo 等 | Windows 優先，另有 macOS／Linux 版（Avalonia、NativeAOT）；MIT；Devolutions 維護 |
| 4,700 | [topgrade-rs/topgrade](https://github.com/topgrade-rs/topgrade) | 偵測已裝工具並一次更新全部 | 命令列 |
| 2 | [mzored/update-all-mac](https://github.com/mzored/update-all-mac) | Homebrew、App Store、npm、pipx、uv 一鍵更新 | Shell 腳本，星數不足，僅備查 |

## 2. Homebrew 圖形介面

| 星數 | 專案 | 技術 | 最近更新 | 備註 |
|---|---|---|---|---|
| 7,096 | [milanvarady/Applite](https://github.com/milanvarady/Applite) | Swift | 2026-09 | Homebrew Cask 的 App Store 式介面 |
| 5,008 | [brunophilipe/Cakebrew](https://github.com/brunophilipe/Cakebrew) | Objective-C | 2024-01 | 已停更 |
| 4,710 | [buresdv/Cork](https://github.com/buresdv/Cork) | SwiftUI | 2026-10 | 選單列更新、標籤、區分主動安裝與相依、服務管理、收編手動安裝的 App；預編譯版收費 |
| 2,845 | [wickenico/WailBrew](https://github.com/wickenico/WailBrew) | Go、Wails、React | 2026-10 | 精簡 Homebrew 介面 |
| 2,694 | [buo/homebrew-cask-upgrade](https://github.com/buo/homebrew-cask-upgrade) | Ruby | 2026-09 | 命令列，更新過期 Cask |

## 3. 應用程式更新器（一般 Mac App）

| 星數 | 專案 | 重點 |
|---|---|---|
| 4,844 | [mangerlahn/Latest](https://github.com/mangerlahn/Latest) | 提示哪些 App 有新版 |
| 12,404 | [mas-cli/mas](https://github.com/mas-cli/mas) | Mac App Store 命令列 |
| 20,886 | [ImranR98/Obtainium](https://github.com/ImranR98/Obtainium) | Android；直接從來源（GitHub release 等）追蹤更新，概念可參考 |

Kegwatch（Homebrew、Cask、App Store、Sparkle 與 Electron 的選單列更新器，免費、不開源）與 MacUpdater、Updatest（付費）沒有公開倉庫，僅備查。

## 4. AI 工具管理（設定與切換，不含用量）

| 星數 | 專案 | 重點 |
|---|---|---|
| 148,821 | [farion1231/cc-switch](https://github.com/farion1231/cc-switch) | 跨平台桌面版，管理 Claude Code、Codex、OpenCode 等的設定 |
| 807 | [dark-hxx/CLI-Manager](https://github.com/dark-hxx/CLI-Manager) | 多專案 AI CLI 工作區 |

## 5. 開發工具版本與環境

| 星數 | 專案 | 重點 |
|---|---|---|
| 8,622 | [XcodesOrg/XcodesApp](https://github.com/XcodesOrg/XcodesApp) | SwiftUI，安裝與切換多個 Xcode 版本；介面參考首選 |
| 7,059 | [geerlingguy/mac-dev-playbook](https://github.com/geerlingguy/mac-dev-playbook) | 以 Ansible 設定 Mac 開發環境 |
| 35,388 | [jdx/mise](https://github.com/jdx/mise) | 開發工具、環境變數、任務執行（命令列） |
| 25,610 | [asdf-vm/asdf](https://github.com/asdf-vm/asdf) | 多語言版本管理（命令列） |
| 27,194 | [Schniz/fnm](https://github.com/Schniz/fnm) | Node 版本管理（命令列） |
| 95,658 | [nvm-sh/nvm](https://github.com/nvm-sh/nvm) | Node 版本管理（命令列） |
| 12,979 | [pypa/pipx](https://github.com/pypa/pipx) | Python 應用程式獨立環境 |
| 4,003 | [version-fox/vfox](https://github.com/version-fox/vfox) | 跨平台版本管理（命令列） |
| 1,877 | [aquaproj/aqua](https://github.com/aquaproj/aqua) | 宣告式 CLI 版本管理 |
| 1,442 | [moonrepo/proto](https://github.com/moonrepo/proto) | 可擴充的多語言版本管理 |

## 6. 弱點稽核與依賴更新

| 星數 | 專案 | 重點 |
|---|---|---|
| 11,272 | [google/osv-scanner](https://github.com/google/osv-scanner) | DevKeeper 使用的同一個 OSV 資料來源（命令列） |
| 38,723 | [aquasecurity/trivy](https://github.com/aquasecurity/trivy) | 弱點、設定錯誤、機密、SBOM 掃描 |
| 13,109 | [anchore/grype](https://github.com/anchore/grype) | 映像檔與檔案系統弱點掃描 |
| 22,891 | [renovatebot/renovate](https://github.com/renovatebot/renovate) | 依賴自動更新；略過、釘選、分組規則的成熟範例 |
| 2,000 | [pyupio/safety](https://github.com/pyupio/safety) | Python 相依套件弱點檢查 |
| 12,520 | [webpro-nl/knip](https://github.com/webpro-nl/knip) | 找出未使用的相依套件 |

## 7. 選單列與清理（相鄰領域，非目前範圍）

| 星數 | 專案 | 重點 |
|---|---|---|
| 72,917 | [tw93/Mole](https://github.com/tw93/Mole) | Mac 清理，命令列加原生 App |
| 7,411 | [momenbasel/PureMac](https://github.com/momenbasel/PureMac) | SwiftUI 清理工具 |
| 744 | [bysiber/cleardisk](https://github.com/bysiber/cleardisk) | 選單列；視覺化並清除開發快取 |
| 18,078 | [matryer/xbar](https://github.com/matryer/xbar) | 把腳本輸出放進選單列 |
| 42,817 | [exelban/stats](https://github.com/exelban/stats) | 選單列系統監控；面板版面參考 |

## 對 DevKeeper 的啟發（待決定，尚未納入計畫）

1. Homebrew 預設只列主動安裝的套件（Cork）：已實作。
2. 勾選後批次更新（Cork）。
3. 系統通知（Kegwatch）。
4. 略過、釘選版本與分組規則（Renovate）。
5. 收編手動安裝的 App 進 Homebrew（Cork、Kegwatch）。
6. 介面與安裝流程參考 XcodesApp。

## 尚未確認

- UniGetUI macOS 版的實際完成度。
- GitHub 搜尋對「功能相似」沒有好辦法，本清單靠關鍵字、主題標籤與已知名稱，可能漏掉知名度低但相關的專案。
